# Creates the login for a person who has none, as UsersController#create does
# (lines 9-23): save the User, then @person.update(user:). The password is a random
# one nobody sees; the person uses Forgot password. No mail is sent.
#
# Who may: set_person (line 43) finds the person in policy_scope(Person). The page
# then authorizes create? on the person and on the User, which those policies don't
# define on every build. A build's own create? applies where it exists, and the gate
# here is the record the login belongs to: UserPolicy#update? with that person, the
# check the same screen's edit makes (line 47). So admins and managers of their teams;
# narrower than a POST on a build with no create?.
#
# Also narrower, by the spec: the page replaces the login of a person who has one, and
# adopts an existing login with that email if it has no person. Both are refused here.
class Mcp::Tools::AddLogin < Mcp::Tool
  include Mcp::PersonWrites

  tool_name "add_login"
  description "Create a login for a person who has none, as their profile's Create Email/Password does. Nobody sees the password: the person uses Forgot password. " \
    "Admins and managers of the person's teams can: anyone else in view gets \"Not allowed\", someone you can't see \"Not found\". " \
    "Refused if they already have a login or the email is in use. Returns the person as get_person shows them, and has_login."
  scope :write
  input_schema(
    properties: {
      person_id: { type: "string", description: "The person's ID (per_)" },
      email: { type: "string", description: "The login's email" }
    },
    required: %w[person_id email],
    closed: true
  )
  output_schema(
    type: "object",
    properties: { person: Mcp::Tools::GetPerson.output_schema, has_login: { type: "boolean", const: true } },
    required: %w[person has_login]
  )

  def call(person_id:, email:)
    person = ctx.find(Person, person_id)
    authorize_login_for!(person)
    invalid_argument!("This person already has a login") if person.user_id.present?

    user = User.new(email: email, password: Devise.friendly_token[0, 20])
    invalid_argument!(user.errors.full_messages.to_sentence) unless user.valid?

    in_all_databases do
      user.save!
      person.update!(user: user)
    end

    changed!(user, person)
    { person: Mcp::Tools::GetPerson.new(ctx).call(person_id: person.neat_id), has_login: true }
  rescue ActiveRecord::RecordNotUnique
    invalid_argument!("Email has already been taken")
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!(e.record.errors.full_messages.to_sentence)
  end

  private

  def authorize_login_for!(person)
    ctx.authorize!(person, :create?) if ctx.defines?(person, :create?)
    ctx.authorize!(User.new, :create?) if ctx.defines?(User.new, :create?)
    # A separate copy: building a User on the person itself would change its login in memory.
    ctx.authorize!(User.new(person: Person.find(person.id)), :update?)
  end
end
