# Withdraws a person's submitted answers, as the response page's Withdraw does
# (FormResponsesController#withdraw, form_responses_controller.rb:68-72):
# FormResponsePolicy#withdraw? (form_response_policy.rb:33), then
# FormSubmission#withdraw!, which revokes its signatures, keeps the answers for the
# next fill, and drops the completion badge through sync_status!.
class Mcp::Tools::WithdrawFormResponse < Mcp::Tool
  include Mcp::FormResponses

  tool_name "withdraw_form_response"
  description "Withdraw a person's submitted answers to a form, as Withdraw response on the response's page does. " \
    "The answers stop counting and their signatures are revoked; filling the form in again starts from them. " \
    "Refusals: Not found for a form or person you can't see, Not allowed for a response you can read but may not withdraw, " \
    "or one with nothing submitted or an unsubmitted update in progress."
  scope :write
  feature :forms
  destructive
  input_schema(
    properties: {
      form_id: { type: "string", description: "The form (frm_ ID)" },
      person_id: { type: "string", description: "The person the response is about (per_ ID)" }
    },
    required: %w[form_id person_id],
    closed: true
  )
  output_schema(Mcp::FormResponses::OUTPUT_SCHEMA)

  def call(form_id:, person_id:)
    form = find_form(form_id)
    response = find_response(form, person_id)
    authorize_response!(response, :withdraw?)

    submission = response.active_submission
    submission.withdraw!(by: ctx.person)
    changed!(submission)
    form_json(form, response)
  end
end
