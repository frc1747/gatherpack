# One person's custom profile fields, as the profile page shows them to this
# viewer: the person must be in policy_scope(Person) and PersonPolicy#show?
# must allow it (as get_person does), then only the fields in
# person.readable_fields_for(viewer) with show_on_profile set, which is what
# people/_fields renders (PersonPolicy#readable_person_fields). That covers
# each read level, guardianship, and badge grants. Values are returned as
# stored for the field's type; a field with no value is null (an unset
# boolean is false, as the page shows "No"). The built-in
# contact and detail fields are included under their sections when the viewer
# may read them, as on the page. Needs the person_fields feature.
#
# For a minor (Mcp.withhold_contact_details?), whoever the viewer is, the built-in
# email, phone, address and birthday fields and custom phone and email fields are
# left out as keys, which is narrower than the page. A built-in field is matched
# on its source, since its key can differ (the phone number's is "phone"). Custom
# fields are matched on type: no type marks an address or a date of birth, so a
# custom string, text or date field holding one can't be told apart and is returned.
#
# get_person adds the same groups as its "fields" key through
# Mcp.person_extensions (see config/initializers/mcp_person_fields.rb).
class Mcp::Tools::GetPersonFields < Mcp::Tool
  WITHHELD_CUSTOM_TYPES = %w[phone email].freeze

  tool_name "get_person_fields"
  description "A person's profile fields that you can see, built-in and custom, grouped by section, each with its type and value. " \
    "Email, phone, address and birthday fields, and custom phone and email fields, are never given here for anyone " \
    "under 18 or with no birthday on file, whoever is asking, so they can be left out even for someone whose details you can see in the app."
  scope :read
  feature :person_fields
  input_schema(properties: { person_id: { type: "string", description: "Person ID (per_...)" } }, required: [ "person_id" ])
  output_schema(
    type: "object",
    properties: {
      person: Mcp::Tool::REF_SCHEMA,
      groups: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: %w[string null], description: "Section name; null for fields outside any section" },
            fields: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  key: { type: "string" },
                  name: { type: "string" },
                  type: { type: "string" },
                  value: { description: "null when empty (false for an unset boolean); a list for multi_select; YYYY-MM-DD for date" }
                },
                required: %w[key name type value]
              }
            }
          },
          required: %w[name fields]
        }
      }
    },
    required: %w[person groups]
  )

  # The groups for a person the viewer may already see. Shared with the
  # get_person extension. Viewer is a Person.
  def self.groups_for(person, viewer)
    fields = person.readable_fields_for(viewer).select(&:show_on_profile)
    fields = fields.reject { |field| contact_detail?(field) } if Mcp.withhold_contact_details?(person)
    rows = person.person_field_values.index_by(&:person_field_id)
    fields.group_by(&:person_field_group).map do |group, group_fields|
      { name: group&.name, fields: group_fields.map { |field| field_json(person, field, rows) } }
    end
  end

  def self.contact_detail?(field)
    return Mcp::MinorRule::WITHHELD_KEYS.include?(field.system_source.delete_prefix("user.")) if field.system?

    WITHHELD_CUSTOM_TYPES.include?(field.data_type)
  end

  def self.field_json(person, field, rows)
    value = field.system? ? person.field_value(field) : field.cast(rows[field.id]&.value)
    value = value.iso8601 if value.is_a?(Date)
    value = nil if value == [] || value == ""
    { key: field.key, name: field.name, type: field.data_type, value: value }
  end

  def call(person_id:)
    person = ctx.find(Person, person_id)
    ctx.authorize!(person, :show?)

    { person: person_json(person), groups: self.class.groups_for(person, ctx.person) }
  end
end
