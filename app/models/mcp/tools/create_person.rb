# Creates a person, as PeopleController#create does (lines 39-52): Person.new with
# the permitted attributes, save, and with an email User.create with a generated
# Spicy::Proton password. The password is never returned or logged; the person uses
# Forgot password. No mail is sent, as on the page (User has no confirmable, and
# Devise's change notifications are off).
#
# Who may: the page authorizes create? (line 40), which PersonPolicy doesn't define
# on every build, and a default that allows everyone isn't a rule (Mcp::Context).
# So a build's own create? applies where it exists, and the gate here is the parent
# record: with team_id, MembershipPolicy#create? on the new membership, as
# add_team_member (admins and the team's managers; the "or themselves" branch can't
# apply to someone new); without a team, there is no parent and only an admin may.
# Narrower than a POST on a build with no create?.
#
# Differs from the page by being all or nothing: the page keeps the person and
# reports a password when User.create fails (line 45), and this refuses and keeps
# nothing. Everything is checked before the first save, so a refusal fires no hooks.
# Duplicates aren't refused, as on the page; clients call find_duplicate_people first.
class Mcp::Tools::CreatePerson < Mcp::Tool
  include Mcp::PersonWrites

  tool_name "create_person"
  description "Create a person, as the People page's New Person does, with a login if you give an email and a team membership if you give a team, all or nothing. " \
    "Admins can create anyone; team managers must give a team they manage; anyone else gets \"Not allowed\", and a team you can't see gets \"Not found\". " \
    "The password is never shown: the person uses Forgot password. Duplicates aren't refused, so call find_duplicate_people first. " \
    "Returns the person as get_person shows them, with has_login."
  scope :write
  input_schema(
    properties: {
      first_name: { type: "string" },
      last_name: { type: "string" },
      display_name: { type: "string", description: "Defaults to first and last name" },
      email: { type: "string", description: "Creates a login with this email" },
      team_id: { type: "string", description: "The team's ID (tm_), to add them to" },
      manager: { type: "boolean", description: "Make them a manager of team_id (default false)" }
    },
    required: %w[first_name last_name],
    closed: true
  )
  output_schema(Mcp::Tools::GetPerson.output_schema.deep_dup.tap do |schema|
    schema[:properties][:has_login] = { type: "boolean" }
    schema[:required] += %w[has_login]
  end)

  def call(first_name:, last_name:, display_name: nil, email: nil, team_id: nil, manager: nil)
    refuse_control_characters!(first_name: first_name, last_name: last_name, display_name: display_name)
    invalid_argument!("manager needs team_id") if manager && team_id.nil?

    person = Person.new({ first_name: first_name, last_name: last_name, display_name: display_name }.compact)
    ctx.authorize!(person, :create?) if ctx.defines?(person, :create?)
    membership = build_membership(person, team_id, manager)
    raise Mcp::NotAllowed unless membership || ctx.user.admin?

    user = build_user(email)
    invalid_argument!(membership.errors.full_messages.to_sentence) if membership && !membership.valid?

    in_all_databases do
      save_person(person)
      if user
        user.person = person
        user.save!
      end
      membership&.save!
    end

    changed!(person, *[ user, membership ].compact)
    Mcp::Tools::GetPerson.new(ctx).call(person_id: person.neat_id).merge(has_login: user.present?)
  rescue ActiveRecord::RecordNotUnique
    invalid_argument!("Email has already been taken")
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!(e.record.errors.full_messages.to_sentence)
  end

  private

  def build_membership(person, team_id, manager)
    return nil if team_id.nil?

    membership = ctx.find(Team, team_id).memberships.build(person: person, manager: manager == true)
    ctx.authorize!(membership, :create?)
    membership
  end

  # A blank email makes no login, as the form's hint says.
  def build_user(email)
    return nil if email.blank?

    user = User.new(email: email, password: Spicy::Proton.pair)
    invalid_argument!(user.errors.full_messages.to_sentence) unless user.valid?
    user
  end
end
