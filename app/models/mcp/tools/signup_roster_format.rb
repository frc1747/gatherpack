# What the sign-up roster tools (move_signup, update_signup, mark_signup,
# mark_all_brought) return: the sign-up as get_signup_sheet's roster row shows it,
# plus the sheet, event and position, as place_signup and remove_signup return them.
# Makes no permission decisions.
module Mcp::Tools::SignupRosterFormat
  include Mcp::Tools::SignupFormat

  RESULT_SCHEMA = {
    type: "object",
    properties: Mcp::Tools::SignupFormat::SIGNUP_SCHEMA[:properties].merge(
      sheet: Mcp::Tools::SignupFormat::SHEET_REF_SCHEMA,
      event: Mcp::Tools::SignupFormat::EVENT_SCHEMA,
      position: Mcp::Tools::SignupFormat::POSITION_SCHEMA
    ),
    required: %w[id status person answer quantity sheet event position]
  }.freeze

  # RESULT_SCHEMA for a retry-safe action, saying whether this call made a difference.
  CHANGE_RESULT_SCHEMA = RESULT_SCHEMA.merge(
    properties: RESULT_SCHEMA[:properties].merge(
      changed: { type: "boolean", description: "False if the sign-up was already in that state, so this call saved nothing new and sent no notices, though signups - update hooks ran again, as on the page" }
    ),
    required: RESULT_SCHEMA[:required] + %w[changed]
  ).freeze

  private

  # GetSignupSheet#roster_json, the row an organizer reads: its test compares the two.
  def roster_result(signup)
    json = signup_json(signup, status: true).merge(note: signup.note.presence)
    json[:on_behalf_of] = person_json(signup.on_behalf_of) if signup.on_behalf_of && signup.on_behalf_of_id != signup.person_id
    json.merge(signup_context(signup))
  end

  def signup_context(signup)
    {
      sheet: { id: signup.signup_sheet.neat_id, title: signup.signup_sheet.title },
      event: event_json(signup.event),
      position: position_json(signup.signup_position)
    }
  end
end
