# Saves answers to a form, and with submit submits them, as the fill page's "Save for
# later" and "Submit" do. FormResponsesController#update
# (form_responses_controller.rb:22-45) is reproduced step by step because the logic is
# in the action: FormResponsePolicy#update?, the response saved if new,
# start_submission!, FormSubmission#assign_answers, save!, sync_status!, then submit!.
# That action never asks submit?, and update? already implies its can_submit?. The
# draft stays when submit! finds something missing, as on the page, so that refusal
# says what was saved. test/integration/mcp_form_responses_page_test.rb compares
# outcomes through the real controller.
#
# The page offers Save and Submit only to someone who can write a question, or on a
# form with none to answer (edit.html.erb:105); others read that it's for someone else
# to fill in. The action itself doesn't check, so a hand-made request gets past the
# page. Here it's Not allowed, before anything changes.
#
# Page answers are keyed by question key; here by question ID, as get_form lists them.
# assign_answers drops an answer to a question the viewer can't write without a word,
# which the tool refuses by name before anything changes. A question the viewer can't
# read, a contact question withheld for a minor and an ID that isn't on the form all
# get the same refusal, so it doesn't confirm any of them.
#
# A question linked to a person field is only stored as an answer until the submission
# becomes active. FormSubmission#apply_to_profile! then writes it through
# Person#assign_field_values, acting: the token's user, and lists what it couldn't
# write in not_copied_to_profile, as the page's badge does. FormAccess#question_writable?
# has already asked PersonFieldAccess#writable? for the question.
#
# Narrower than the page for a minor: see above. A contact answer someone entered on
# the page stays in the draft and is still submitted with it, since it never reaches
# the client. A required contact question that is blank still blocks the submit, as on
# the page, and the message doesn't name it, though the refusal itself shows that one
# is blank.
#
# The form has no question type that takes an upload or a widget: every type in
# FieldValueType is a value a client can send. Input is checked before normalize, which
# would read "no" as ticked. A very long date string is refused here because the page
# crashes on it (Date.iso8601's length limit isn't a Date::Error).
class Mcp::Tools::SaveFormAnswers < Mcp::Tool
  include Mcp::FormResponses
  include Mcp::PersonWrites

  MAX_DATE_LENGTH = 32

  tool_name "save_form_answers"
  description "Save answers to a form for a person, as Save for later on the form's page does; with submit: true, also submit them, as its Submit does. " \
    "Takes answers by question ID from get_form: a string, true or false for a yes/no, a whole number, a list for multiple choice, YYYY-MM-DD for a date, null to clear. " \
    "Only the given answers change; the result has the saved answers. Changing a submitted version's answers removes any signatures already given. " \
    "If submit finds required answers missing, the answers stay saved as a draft and the refusal lists what's missing by question. " \
    "Answers to questions that update the profile are saved there when the response becomes complete. " \
    "Contact questions (see get_form) can't be answered for anyone under 18 or with no birthday on file. " \
    "Refusals: Not found for a form or person you can't see, Not allowed for a response or question you can't answer; nothing is saved then."
  scope :write
  feature :forms
  destructive
  mask_argument :answers
  input_schema(
    properties: {
      form_id: { type: "string", description: "The form (frm_ ID)" },
      person_id: { type: "string", description: "The person the response is about (per_ ID)" },
      answers: { type: "object", description: "{ question_id: value }. Empty is fine with submit: true" },
      submit: { type: "boolean", description: "Also submit, as the page's Submit does (default false)" }
    },
    required: %w[form_id person_id answers],
    closed: true
  )
  output_schema(Mcp::FormResponses::OUTPUT_SCHEMA)

  def call(form_id:, person_id:, answers:, submit: false)
    form = find_form(form_id)
    response = find_response(form, person_id)
    authorize_response!(response, :update?)
    raise Mcp::NotAllowed unless fill_page_offers_submit?(response)

    access = access_for(response)
    input = page_input(response, access, answers)
    before = side_state(response)
    submission = save_draft(response, access, input)
    changed!(submission, *also_changed(response, before))
    return form_json(form, response) unless submit

    errors = submission.submit!(ctx.person, access)
    refuse_missing!(response, errors) if errors.any?

    changed!(submission, *profile_records(submission), *also_changed(response, before))
    form_json(form, response)
  end

  private

  # In one transaction per database, so a refused answer leaves no audit row for the
  # response or draft it rolled back. The page leaves those audit rows behind.
  def save_draft(response, access, input)
    in_all_databases do
      response.save! if response.new_record?
      submission = response.start_submission!(ctx.person)
      errors = submission.assign_answers(input, access)
      refuse_answers!(response, errors) if errors.any?

      submission.save!
      response.sync_status!
      submission
    end
  end

  # { key => what the form would post }, or a refusal naming what can't be answered.
  def page_input(response, access, answers)
    writable = open_questions(response).select { |question| access.question_writable?(question) }.index_by(&:neat_id)
    refused = answers.keys - writable.keys
    refuse_questions!(response, access, refused) if refused.any?

    answers.to_h { |id, value| [ writable[id].key, form_input(writable[id], value) ] }
  end

  # Names only a question this viewer can read and the client may see. Anything else
  # is counted, never echoed: a client's key could hold anything.
  def refuse_questions!(response, access, ids)
    visible = open_questions(response).select { |question| access.question_readable?(question) }.index_by(&:neat_id)
    named, others = ids.partition { |id| visible.key?(id) }
    parts = named.map { |id| visible[id].label }
    parts << "#{others.size} #{"question".pluralize(others.size)} that can't be answered here" if others.any?
    raise Mcp::NotAllowed, "Not allowed: #{parts.to_sentence}. Nothing was saved."
  end

  # What the form would send for this value. The form can only send a checkbox, a list
  # of choices or text, so refuse anything else rather than let the type's conversion guess.
  def form_input(question, value)
    case question.value_type.data_type
    when "boolean"
      invalid_argument!("#{question.label} takes true or false") unless [ true, false, nil ].include?(value)
      value ? "1" : "0"
    when "multi_select"
      choices = value.nil? ? [] : Array(value)
      invalid_argument!("#{question.label} takes a list of choices") unless choices.all? { |choice| choice.is_a?(String) && choice.present? }
      choices
    when "integer"
      invalid_argument!("#{question.label} takes a whole number") unless value.nil? || value.is_a?(Integer) || value.is_a?(String)
      value.to_s
    else
      text_input(question, value)
    end
  end

  def text_input(question, value)
    invalid_argument!("#{question.label} takes text") unless value.nil? || value.is_a?(String)
    type = question.value_type.data_type
    invalid_argument!("#{question.label} takes one line") if type != "text" && value.to_s.match?(/[[:cntrl:]]/)
    invalid_argument!("#{question.label} isn't a valid date") if type == "date" && value.to_s.length > MAX_DATE_LENGTH
    value.to_s
  end

  def refuse_answers!(response, errors)
    invalid_argument!("Nothing was saved. #{by_question(response, errors)}")
  end

  def refuse_missing!(response, errors)
    invalid_argument!("Your answers were saved as a draft, but not submitted. Still needed: #{by_question(response, errors)}")
  end

  # { key => error } by label and ID. A withheld question is only counted, in words
  # that don't say which, so the client isn't told to fill in what it can't.
  def by_question(response, errors)
    open = open_questions(response).index_by(&:key)
    named, withheld = errors.partition { |key, _error| open.key?(key) }
    parts = named.map { |key, error| "#{open[key].label} (#{open[key].neat_id}) #{error}" }
    parts << "another required question, which has to be completed on the form's page" if withheld.any?
    "#{parts.join("; ")}."
  end
end
