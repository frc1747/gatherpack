# People who may already be the one a client is about to create: the same first and
# last name, ignoring surrounding space and case, or the same login email. Only
# people in policy_scope(Person), as the people index lists them, so a match outside
# it isn't revealed. The email itself is never returned. has_login is given for an
# email match, which implies it, and where PersonPolicy#show? allows the profile,
# which says whether a login exists; otherwise it's left out.
class Mcp::Tools::FindDuplicatePeople < Mcp::Tool
  tool_name "find_duplicate_people"
  description "Find people you can see who have the same name, ignoring case and surrounding spaces, or the same login email; call it before create_person. " \
    "Someone you can't see is left out, so an empty list doesn't prove nobody matches. Emails are never returned."
  scope :read
  input_schema(
    properties: {
      first_name: { type: "string" },
      last_name: { type: "string" },
      email: { type: "string" },
      limit: limit_property
    },
    required: %w[first_name last_name]
  )
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" },
            name: { type: "string" },
            matched_on: { type: "array", items: { type: "string", enum: %w[name email] } },
            has_login: { type: "boolean" }
          },
          required: %w[id name matched_on]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(first_name:, last_name:, email: nil, limit: DEFAULT_LIMIT)
    invalid_argument!("Give a name or an email") if (first_name.blank? || last_name.blank?) && email.blank?

    scope = ctx.policy_scope(Person)
    by_name = name_matches(scope, first_name, last_name)
    by_email = email_matches(scope, email)
    email_ids = by_email.pluck(:id)
    name_ids = by_name.pluck(:id)

    list(scope.where(id: name_ids + email_ids).order(:last_name, :first_name, :id), limit: limit) do |person|
      item = person_json(person).merge(matched_on: matched_on(person, name_ids, email_ids))
      item[:has_login] = person.user_id.present? if email_ids.include?(person.id) || ctx.allowed?(person, :show?)
      item
    end
  end

  private

  def name_matches(scope, first_name, last_name)
    return scope.none if first_name.blank? || last_name.blank?

    scope.where("LOWER(BTRIM(first_name)) = LOWER(BTRIM(?)) AND LOWER(BTRIM(last_name)) = LOWER(BTRIM(?))", first_name.strip, last_name.strip)
  end

  # Devise stores emails stripped and in lower case.
  def email_matches(scope, email)
    return scope.none if email.blank?

    scope.where(user_id: User.where(email: email.strip.downcase).select(:id))
  end

  def matched_on(person, name_ids, email_ids)
    [ ("name" if name_ids.include?(person.id)), ("email" if email_ids.include?(person.id)) ].compact
  end
end
