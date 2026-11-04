# A form's questions in order, and with person_id that person's response state.
# Without person_id the gate is FormPolicy#show? (forms_controller.rb:29 and :150,
# the form's status and results pages). With person_id it is FormResponsePolicy#show?
# (form_responses_controller.rb:7), the response page's own gate: a member or
# guardian has no form page but does have a fill page, so they ask for their own or
# their ward's response. The questions are then the fill page's
# (form_responses/edit.html.erb:60-79): what isn't an answer, and the answerable ones
# passing FormAccess#question_readable?.
#
# Answers aren't returned: form_answers reads those. Narrower than the page for a
# minor (Mcp::MinorRule), whoever the viewer is: contact questions are left out, by
# the rule in Mcp::Tools::FormAnswers, with no per-person reason. The list without
# person_id holds no one's details, so the rule has nothing to judge there.
class Mcp::Tools::GetForm < Mcp::Tool
  include Mcp::FormResponses

  tool_name "get_form"
  description "A form's questions in order, with each one's type, options and whether it is required, as its pages show them. " \
    "Give person_id (your own, or someone you may answer for) for the questions shown to that person and where their response stands; " \
    "it's needed unless you can see the form's results. " \
    "Questions linked to the built-in email, phone, address or birthday fields, questions of phone or email type, and questions that were either of those earlier " \
    "are left out for anyone under 18 or with no birthday on file, whoever is asking. " \
    "Refusals: Not found for a form or person you can't see, Not allowed for a form you can see only with person_id."
  scope :read
  feature :forms
  input_schema(
    properties: {
      form_id: { type: "string", description: "The form (frm_ ID)" },
      person_id: { type: "string", description: "The person the response is about (per_ ID)" }
    },
    required: %w[form_id]
  )
  output_schema(Mcp::FormResponses::OUTPUT_SCHEMA)

  def call(form_id:, person_id: nil)
    form = find_form(form_id)
    return form_json(form) if person_id.nil? && viewer_sees_form?(form)

    response = find_response(form, person_id)
    authorize_response!(response, :show?)
    form_json(form, response)
  end

  private

  def viewer_sees_form?(form)
    return true if ctx.allowed?(form, :show?)

    form.readable_subjects_for(ctx.person).exists? ? raise(Mcp::NotAllowed) : not_found!
  end
end
