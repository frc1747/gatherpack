# Signs a submitted version, as the response page's Sign does
# (FormResponsesController#sign, form_responses_controller.rb:75-93):
# FormResponsePolicy#sign?, the signature question picked from the form's, and
# FormSubmission#sign!, which checks the signer's role for that question
# (FormAccess#signing_role) and that typed_name is their own name. Those two are all
# the page asks for. The signer is always the token's user. The last signature
# activates the submission.
#
# The page also records the request's IP address and user agent, which a tool can't
# see (Mcp::Context doesn't carry them): the IP stays empty and the user agent names
# the client, so a signature given this way can be told apart.
class Mcp::Tools::SignFormResponse < Mcp::Tool
  include Mcp::FormResponses

  USER_AGENT = "MCP client".freeze

  tool_name "sign_form_response"
  description "Records a signature in the member's name, so confirm with the member first. " \
    "Signs a submitted response as Sign on the response's page does, recording you as the signer, in the role get_form's can_sign allows: yourself, a guardian, or a leader recording a paper form. " \
    "typed_name must be your own full name, as on your account. " \
    "Changing the answers later needs a new signature. " \
    "Refusals: Not found for a form, person or question you can't see, Not allowed for a signature you may not give, or a response with nothing waiting for your signature."
  scope :write
  feature :forms
  mask_argument :typed_name
  input_schema(
    properties: {
      form_id: { type: "string", description: "The form (frm_ ID)" },
      person_id: { type: "string", description: "The person the response is about (per_ ID)" },
      question_id: { type: "string", description: "The signature question (frmq_ ID), from get_form" },
      typed_name: { type: "string", description: "Your own full name, as on your account" }
    },
    required: %w[form_id person_id question_id typed_name],
    closed: true
  )
  output_schema(Mcp::FormResponses::OUTPUT_SCHEMA)

  def call(form_id:, person_id:, question_id:, typed_name:)
    form = find_form(form_id)
    response = find_response(form, person_id)
    authorize_response!(response, :sign?)
    question = form.signature_questions.detect { |candidate| candidate.neat_id == question_id } || not_found!

    access = access_for(response)
    submission = response.open_submission
    error = submission.sign!(question, signer: ctx.person, typed_name: typed_name, access: access, user_agent: user_agent)
    if error
      raise Mcp::NotAllowed unless access.can_sign?(question)

      invalid_argument!(error)
    end

    submission.reload
    changed!(submission.signature_for(question), submission, *profile_records(submission))
    form_json(form, response)
  end

  private

  def user_agent
    [ USER_AGENT, ctx.application&.name ].compact.join(": ")
  end
end
