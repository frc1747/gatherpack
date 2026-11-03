# Set one person field on one person, as the person's edit page does: the person
# must be in policy_scope(Person) and PersonPolicy#update? must allow it, the
# field must be in person.writable_fields_for(viewer), and the value goes through
# Person#assign_field_values and save, so each field's write level, badge grants,
# type rules, required check, audit history and "person_fields - value changed"
# hooks all apply. A field the viewer can't write and a key that doesn't exist get
# the same refusal, so it doesn't confirm a field exists.
#
# Narrower than the page: a minor's contact details never go through MCP
# (Mcp::MinorRule), so the fields get_person_fields leaves out for a minor can't be
# set either, whoever is asking. That also stops a minor's birthday being changed
# to an adult's, which would lift the rule. The result never gives the old value.
class Mcp::Tools::SetPersonField < Mcp::Tool
  tool_name "set_person_field"
  description "Set one profile field on a person, following the same rules as editing their profile: the field's write level decides who can change it. " \
    "Use the field's key from get_person_fields. This replaces the current value. Send null to clear it, true or false for a yes/no field, " \
    "a whole number for a number field, a list for a multiple-choice field, and YYYY-MM-DD for a date. A required field can't be cleared, " \
    "and a blank required field elsewhere on the person blocks the change until it's completed. " \
    "The built-in email can't be set here for anyone. The built-in phone, address and birthday fields, and custom fields of phone or email type, " \
    "can't be set here for anyone under 18 or with no birthday on file, so changing or clearing a birthday can lock them, and only the profile page can undo it. " \
    "Returns the field's new value."
  scope :write
  feature :person_fields
  destructive
  input_schema(
    properties: {
      person_id: { type: "string", description: "The person's ID (per_)" },
      field_key: { type: "string", description: "The field's key, from get_person_fields" },
      value: { type: %w[string integer boolean array null], items: { type: "string" }, description: "The new value; null clears the field" }
    },
    required: %w[person_id field_key value]
  )
  output_schema(
    type: "object",
    properties: {
      person: REF_SCHEMA,
      key: { type: "string" },
      name: { type: "string" },
      type: { type: "string" },
      value: { description: "The field's value now: null when empty (false for an unset boolean); a list for multi_select; YYYY-MM-DD for date" },
      changed: { type: "boolean", description: "False when the field already had this value" }
    },
    required: %w[person key name type value changed]
  )

  def call(person_id:, field_key:, value:)
    person = ctx.find(Person, person_id)
    ctx.authorize!(person, :update?)
    field = person.writable_fields_for(ctx.person).find { |candidate| candidate.key == field_key }
    raise Mcp::NotAllowed unless field
    # Before the new value is assigned: it could be the birthday this depends on.
    minor = Mcp.withhold_contact_details?(person)
    raise Mcp::NotAllowed if minor && Mcp::Tools::GetPersonFields.contact_detail?(field)

    before = person.field_value(field)
    row_before = person.person_field_values.find { |row| row.person_field_id == field.id }
    person.assign_field_values({ field.key => form_input(field, value) }, acting: ctx.person)
    invalid_argument!(save_problem(person, minor)) unless person.save

    person.person_field_values.reset
    now = person.field_value(field)
    rows = person.person_field_values.index_by(&:person_field_id)
    # The audit row is on the value's own row for a custom field.
    changed!(field.system? ? person : rows[field.id] || row_before) if now != before

    Mcp::Tools::GetPersonFields.field_json(person, field, rows).merge(person: person_json(person), changed: now != before)
  end

  private

  # The save stays blocked by a blank required field, as on the page, but the
  # message can't name a field withheld from this person. The call still fails
  # until that field is filled in, which the viewer, who can write it on the page,
  # could find out there.
  def save_problem(person, minor)
    if minor
      withheld = person.writable_fields_for(ctx.person).select { |field| Mcp::Tools::GetPersonFields.contact_detail?(field) }.map(&:key)
      return "Another required field is blank; complete it on their profile page." if person.errors.attribute_names.map(&:to_s).intersect?(withheld)
    end

    person.errors.full_messages.to_sentence
  end

  # What the form would send for this value. The form can only send a checkbox,
  # a list of choices, or one line of text, so refuse anything else rather than
  # let the field's conversion guess: "no" would cast to true.
  def form_input(field, value)
    case field.data_type
    when "boolean"
      invalid_argument!("#{field.name} takes true or false") unless [ true, false, nil ].include?(value)
      value ? "1" : "0"
    when "multi_select"
      choices = value.nil? ? [] : Array(value)
      invalid_argument!("#{field.name} takes a list of choices") unless choices.all? { |choice| choice.is_a?(String) && choice.present? }
      choices
    when "integer"
      invalid_argument!("#{field.name} takes a whole number") unless value.nil? || value.is_a?(Integer) || value.is_a?(String)
      value.to_s
    else
      invalid_argument!("#{field.name} takes text") unless value.nil? || value.is_a?(String)
      invalid_argument!("#{field.name} takes one line") if field.data_type != "text" && value.to_s.match?(/[[:cntrl:]]/)
      value.to_s
    end
  end
end
