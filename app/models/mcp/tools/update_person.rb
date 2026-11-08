# Changes a person's base profile, as PeopleController#update does: set_person (line
# 103, in policy_scope(Person), then PersonPolicy#update?), person_params (line 110)
# for which attributes, and save. Where a build's policy defines update_profile?, the
# page's person_params keeps these attributes only if it allows them and otherwise
# drops them; this refuses by name instead.
#
# email: the page permits it, but Person#email is a plain accessor, so the update
# stores nothing and reports success. The login's email changes on
# UsersController#update. So this refuses email by name for everyone, on any person,
# and says nothing that depends on their age (Mcp::MinorRule). The other details on
# the form (phone, birthday, address, ...) aren't arguments, and being a closed schema
# they're refused by name rather than dropped; a build with person fields sets them
# through its own tool, which applies write levels and the minors rule.
class Mcp::Tools::UpdatePerson < Mcp::Tool
  include Mcp::PersonWrites

  PROFILE_ARGUMENTS = %w[first_name last_name display_name bio].freeze

  tool_name "update_person"
  description "Change a person's name, display name or bio, as Edit Profile does; only what you send changes, and an empty string clears it. " \
    "You can change yourself, or anyone if you're an admin or manage one of their teams: anyone else in view gets \"Not allowed\", someone you can't see \"Not found\". " \
    "A login's email can't be changed here for anyone: that's the person's Change Email/Password page. " \
    "Returns the person as get_person shows them."
  scope :write
  # It can't be used for anyone, so it isn't kept either.
  mask_argument :email
  input_schema(
    properties: {
      person_id: { type: "string", description: "The person's ID (per_)" },
      first_name: { type: "string" },
      last_name: { type: "string" },
      display_name: { type: "string", description: "Blank resets it to first and last name" },
      bio: { type: "string", description: "Markdown" },
      email: { type: "string", description: "Always refused: see the description" }
    },
    required: %w[person_id],
    closed: true
  )
  output_schema(Mcp::Tools::GetPerson.output_schema)

  def call(person_id:, email: nil, **attributes)
    person = ctx.find(Person, person_id)
    ctx.authorize!(person, :update?)
    raise Mcp::NotAllowed, "Not allowed: email. Change it on the person's Change Email/Password page" unless email.nil?
    invalid_argument!("Give at least one of #{PROFILE_ARGUMENTS.to_sentence(last_word_connector: " or ")}") if attributes.empty?
    if ctx.defines?(person, :update_profile?) && !ctx.allowed?(person, :update_profile?)
      raise Mcp::NotAllowed, "Not allowed: #{attributes.keys.to_sentence}"
    end
    refuse_control_characters!(attributes.except(:bio))

    person.assign_attributes(attributes)
    in_all_databases { save_person(person) }

    changed!(person) if person.saved_changes?
    Mcp::Tools::GetPerson.new(ctx).call(person_id: person.neat_id)
  end
end
