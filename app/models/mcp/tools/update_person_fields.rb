# Set several profile fields on one person in one call, as the person's edit page does
# with the same input (PeopleController#update, app/controllers/people_controller.rb:56-58):
# the person must be in policy_scope(Person) (set_person, line 105) and
# PersonPolicy#update? must allow it, and the values go through
# Person#assign_field_values and save. The page first drops every key outside
# policy(@person).writable_person_fields (person_field_value_params, line 127), and
# silently; this refuses them by name instead, all of them, and nothing is changed
# unless every key is writable. Once assigned, the save runs each field's type rules, the
# required check, audit history and "person_fields - value changed" hooks, as on the
# page, and fails as a whole: the values and the person are saved together or not at
# all. A key that doesn't exist, one the viewer can't write and one withheld from a
# minor get the same refusal, so it confirms nothing about the field or the person's age.
#
# Only the given fields change: assign_field_values on this build visits only the keys it
# is given (it checks every writable required field, which blocks the save as on the page).
#
# Narrower than the page: a minor's contact details never go through MCP (Mcp::MinorRule),
# as in set_person_field, which this shares its value handling with (Mcp::PersonFieldInput).
# Also, a date string over 128 characters, and a built-in date (the birthday) outside the
# range Postgres can store, are refused without quoting them; the page crashes on both
# (ArgumentError, ActiveRecord::StatementInvalid).
class Mcp::Tools::UpdatePersonFields < Mcp::Tool
  include Mcp::PersonFieldInput
  include Mcp::PersonWrites

  tool_name "update_person_fields"
  description "Set several profile fields on one person, following the same rules as editing their profile: each field's write level decides who can change it, and the fields not listed stay as they are. " \
    "Use the keys from list_person_fields. Send null to clear one, true or false for a yes/no field, a whole number for a number field, " \
    "a list for a multiple-choice field, and YYYY-MM-DD for a date. All or nothing: if any field can't be written by you, " \
    "or is a minor's contact detail, the refusal names the keys and nothing is changed. " \
    "A required field can't be cleared, and a blank required field elsewhere on the person blocks the change until it's completed. " \
    "The built-in email can't be set here for anyone. The built-in phone, address and birthday fields, and custom fields of phone or email type, " \
    "can't be set here for anyone under 18 or with no birthday on file, so changing or clearing a birthday can lock them, and only the profile page can undo it. " \
    "Someone you can't see gets \"Not found\". Returns the person's fields as get_person_fields shows them."
  scope :write
  feature :person_fields
  destructive
  # The keys are field keys and stay in the log; what they're set to doesn't.
  mask_argument :values, with: ->(values) { values.is_a?(Hash) ? values.transform_values { MASKED } : MASKED }
  input_schema(
    properties: {
      person_id: { type: "string", description: "The person's ID (per_)" },
      values: {
        type: "object",
        description: "Field key => new value; null clears the field",
        additionalProperties: { type: %w[string integer boolean array null], items: { type: "string" } }
      }
    },
    required: %w[person_id values],
    closed: true
  )
  output_schema(Mcp::Tools::GetPersonFields.output_schema)

  def call(person_id:, values:)
    person = ctx.find(Person, person_id)
    ctx.authorize!(person, :update?)
    invalid_argument!("Give at least one field in values") if values.empty?

    # Before anything is assigned: one of the values could be the birthday this depends on.
    minor = Mcp.withhold_contact_details?(person)
    writable = person.writable_fields_for(ctx.person).index_by(&:key)
    fields = values.keys.to_h { |key| [ key, writable[key] ] }
    refused = fields.select { |_key, field| field.nil? || (minor && Mcp::Tools::GetPersonFields.contact_detail?(field)) }.keys
    raise Mcp::NotAllowed, "Not allowed: #{refused.to_sentence}" if refused.any?

    inputs = fields.to_h { |key, field| [ key, form_input(field, values[key]) ] }
    fields.each { |key, field| refuse_unstorable_date!(field, inputs[key]) }
    before = fields.values.to_h { |field| [ field, person.field_value(field) ] }
    rows_before = person.person_field_values.index_by(&:person_field_id)

    in_all_databases do
      person.assign_field_values(inputs, acting: ctx.person)
      invalid_argument!(save_problem(person, minor)) unless person.save
    end

    person.person_field_values.reset
    rows = person.person_field_values.index_by(&:person_field_id)
    changed = fields.values.select { |field| person.field_value(field) != before[field] }
    # The audit row is on the value's own row for a custom field.
    records = changed.map { |field| field.system? ? person : rows[field.id] || rows_before[field.id] }.uniq
    changed!(*records) if records.any?

    { person: person_json(person), groups: Mcp::Tools::GetPersonFields.groups_for(person, ctx.person) }
  end

  private

  # Date.iso8601 raises a plain ArgumentError past 128 characters, which no date needs,
  # so a longer string is refused for any date field. Past that, Postgres dates run from
  # 4713 BC to 5874897 AD; a custom field keeps its date as JSON text, so only a built-in
  # column can overflow.
  def refuse_unstorable_date!(field, input)
    return unless field.type_date? && input.is_a?(String)

    invalid_argument!("#{field.name} isn't a valid date") if input.length > 128
    return unless field.system?

    date = Date.iso8601(input.strip)
    invalid_argument!("#{field.name} isn't a valid date") unless date.between?(Date.new(-4712, 1, 1), Date.new(5_874_897, 12, 31))
  rescue Date::Error
    nil # normalize refuses it, with the form's message
  end
end
