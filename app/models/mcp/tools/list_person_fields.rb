# The person field definitions, for a client that is about to read or write them. The
# page for this, PersonFieldsController#index, is admin-only (PersonFieldPolicy is an
# AdminPolicy, whose scope returns every row), so there's no policy to apply to a
# non-admin, who meets definitions only on the profile and edit forms. So an admin gets
# every field in use, as that page lists them (custom fields only while the feature is
# on, no archived ones), whether or not anyone it applies to exists yet. Anyone else gets
# a field only if a page would show it to them: they can read it for at least one person
# they can see (PersonField#readable_subjects_for, which "must agree with
# PersonFieldAccess for every subject", within policy_scope(Person)) and it is shown on
# the profile (people/_fields), or they can write it for someone they can see (the edit
# form). No permission levels or badge grants are given. "writable" is the same question
# for writing, and says nothing about a particular person: update_person_fields decides
# that, and refuses a minor's contact details whoever asks (Mcp::MinorRule). The
# built-in email is never writable.
class Mcp::Tools::ListPersonFields < Mcp::Tool
  tool_name "list_person_fields"
  description "The profile fields, built-in and custom, with their key, name, section, type, choices, range, whether they're required, " \
    "and whether you can write them for anyone. Use the key with get_person_fields, set_person_field and update_person_fields. " \
    "Admins get every active field; anyone else gets the fields they can see on some person's profile. Archived fields are left out."
  scope :read
  feature :person_fields
  input_schema(properties: {})
  output_schema(
    type: "object",
    properties: {
      fields: {
        type: "array",
        items: {
          type: "object",
          properties: {
            key: { type: "string" },
            name: { type: "string" },
            group: { type: %w[string null], description: "Section name; null for fields outside any section" },
            type: { type: "string" },
            choices: { type: %w[array null], items: { type: "string" }, description: "The options of a select or multi_select field" },
            min: { type: %w[string null], description: "Lowest allowed value of an integer or date field" },
            max: { type: %w[string null], description: "Highest allowed value of an integer or date field" },
            required: { type: "boolean", description: "A blank required field blocks changes to the person until it's filled in" },
            writable: { type: "boolean", description: "Whether you can write it for at least one person; the built-in email never" }
          },
          required: %w[key name group type choices min max required writable]
        }
      }
    },
    required: %w[fields]
  )

  def call
    viewer = ctx.person
    fields = PersonField.in_use.ordered.includes(:person_field_group, :team, person_field_badge_grants: :badge).to_a
    return { fields: fields.map { |field| field_json(field, !field.system_read_only?) } } if viewer.admin?

    visible = ctx.policy_scope(Person)
    listed = fields.filter_map do |field|
      writable = visible.where(id: field.writable_subjects_for(viewer).select(:id)).exists?
      readable = field.show_on_profile && visible.where(id: field.readable_subjects_for(viewer).select(:id)).exists?
      [ field, writable ] if writable || readable
    end
    { fields: listed.map { |field, writable| field_json(field, writable) } }
  end

  private

  def field_json(field, writable)
    ranged = field.type_integer? || field.type_date?
    {
      key: field.key,
      name: field.name,
      group: field.person_field_group&.name,
      type: field.data_type,
      choices: (field.choice_list if field.type_select? || field.type_multi_select?),
      min: (field.min.presence if ranged),
      max: (field.max.presence if ranged),
      required: field.required?,
      writable: writable
    }
  end
end
