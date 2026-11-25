# What the token tools share. A token's value is what logs its holder in at the kiosk,
# so no tool returns one in full, to anyone. See masked.
module Mcp::TokenRecords
  SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      person: { anyOf: [ Mcp::Tool::REF_SCHEMA, { type: "null" } ] },
      masked_value: { type: "string" },
      length: { type: "integer" }
    },
    required: %w[id person masked_value length]
  }.freeze
  DOT = "•".freeze
  CLUE_LENGTH = 2

  # First two and last two characters with dots between (17••••••••34). Those four would
  # be the whole of a value of four characters or fewer, so that's all dots.
  def self.masked(value)
    value = value.to_s
    return DOT * value.length if value.length <= CLUE_LENGTH * 2

    "#{value.first(CLUE_LENGTH)}#{DOT * (value.length - CLUE_LENGTH * 2)}#{value.last(CLUE_LENGTH)}"
  end

  private

  # person is null for a token held by something else, such as a hook.
  def token_json(token)
    holder = token.tokenable
    {
      id: token.neat_id,
      person: holder.is_a?(Person) ? person_json(holder) : nil,
      masked_value: Mcp::TokenRecords.masked(token.value),
      length: token.value.to_s.length
    }
  end
end
