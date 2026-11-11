# Gives a person a token, as TokensController#create does (lines 25-37): build from the
# permitted attributes (line 63), authorize create?, refuse a value already in use, save.
# Token's before_save normalizes the value (rfidify).
#
# The page finds a duplicate by its normalized form, and its redirect goes to the
# holder's token. This compares the raw and the normalized value, so a reader's other
# format of a card already issued is refused, as there, and doesn't say whose it is. Only after
# create?, so nobody else can test a value.
#
# Narrower than the page: only people (its form offers hooks too), and only those in
# policy_scope(Person), as the form's search is, since this result names them.
class Mcp::Tools::AddToken < Mcp::Tool
  include Mcp::TokenRecords

  tool_name "add_token"
  description "Give a person a scan card or tag, as New Token does, for admins and managers; anyone else in view gets \"Not allowed\", and someone you can't see is \"Not found\". " \
    "A value already in use is refused, without saying whose it is. The value is normalized as the page does and returned masked, like list_tokens."
  scope :write
  feature :tokens
  mask_argument :value, with: ->(value) { Mcp::TokenRecords.masked(Token.rfidify(value)) }
  input_schema(
    properties: {
      person_id: { type: "string", description: "The person's ID (per_)" },
      value: { type: "string", description: "What the card or tag carries" }
    },
    required: %w[person_id value],
    closed: true
  )
  output_schema(Mcp::TokenRecords::SCHEMA)

  def call(person_id:, value:)
    person = ctx.find(Person, person_id)
    token = Token.new(tokenable: person, value: value)
    ctx.authorize!(token, :create?)
    invalid_argument!("The value can't contain line breaks or control characters") if value.match?(Mcp::PunchRecords::SINGLE_LINE_REFUSED)
    invalid_argument!("That value is already in use") if Token.exists?(value: [ value, Token.rfidify(value) ])
    invalid_argument!(token.errors.full_messages.to_sentence) unless token.save

    changed!(token)
    token_json(token)
  end
end
