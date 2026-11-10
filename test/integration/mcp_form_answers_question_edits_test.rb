require "test_helper"
require_relative "../support/mcp_world"
require_relative "../support/mcp_forms_world"

# Answers are stored by key and stay active when a question is edited, so each
# edit here, made as the form's manager, reads an old answer through a new
# definition. A minor's contact answer must stay out, and an adult's stays in.
#
# This build keeps an answered question's type and link and never reuses a key,
# on the page and in the model (see the first test). So those edits are made here
# behind the validations, as data from before the rule or a script can have them:
# the tool has to hold for those rows too.
class McpFormAnswersQuestionEditsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld
  include McpFormsWorld

  ANSWERS = {
    "linked_email" => "linked@example.com", "linked_phone" => "555-0101", "linked_address" => "1 Main St", "linked_birthday" => "2010-05-06",
    "own_phone" => "555-0102", "pick" => "kept"
  }.freeze

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_forms_world
    PersonField.ensure_system_fields!

    person(:ward).update!(birthday: 16.years.ago.to_date)
    person(:alpha_member).update!(birthday: Date.new(1990, 5, 6))

    @form = create_world_form("Contacts", @alpha)
    { "linked_email" => "user.email", "linked_phone" => "phone_number", "linked_address" => "address", "linked_birthday" => "birthday" }.each do |key, source|
      @form.form_questions.create!(kind: :input, key: key, label: key.humanize, person_field: PersonField.system_field(source), profile_mode: :prefill)
    end
    @form.form_questions.create!(kind: :input, key: "own_phone", label: "Own phone", data_type: :phone)
    @form.form_questions.create!(kind: :input, key: "pick", label: "Pick", data_type: :string)
    @form.form_questions.reset
    @custom_text = PersonField.create!(name: "Custom text", data_type: :string, read_permission: "everyone", write_permission: "everyone")

    respond_to_form(@form, :ward, as: :guardian, answers: ANSWERS)
    respond_to_form(@form, :alpha_member, as: :alpha_member, answers: ANSWERS)
    sign_in user(:alpha_manager)
  end

  def question(key)
    @form.form_questions.find_by!(key: key)
  end

  def edit_question(key, form: @form, **attributes)
    question = form.form_questions.find_by!(key: key)
    return edit_answered_question(question, form, attributes) if question.answered?

    patch form_question_path(form, question), params: { form_question: attributes }
    assert_response :see_other
  end

  # The audit history and the change to the form's content still happen. valid?
  # runs the callback that clears what no longer applies, as a save from the page does.
  def edit_answered_question(question, form, attributes)
    question.assign_attributes(attributes)
    question.valid?
    question.save!(validate: false)
    form.reload.publish_changes!(reconfirm: false)
  end

  def replace_with_plain_question(form, key, label)
    delete form_question_path(form, form.form_questions.find_by!(key: key))
    assert_response :see_other

    form.form_questions.build(kind: :input, key: key, label: label, data_type: :string, position: form.form_questions.maximum(:position).to_i + 1).save!(validate: false)
    form.reload.publish_changes!(reconfirm: false)
  end

  def signed_in_as(name)
    sign_out :user
    sign_in user(name)
    yield
  ensure
    sign_out :user
    sign_in user(:alpha_manager)
  end

  def save_answers(form, subject, answers, submit: false)
    params = { form_response: { answers: answers } }
    params[:submit] = "1" if submit
    patch form_response_path(form, person(subject)), params: params
    assert_response :see_other
  end

  def form_answers_values(form, name, viewer: :alpha_manager)
    result = call_tool("form_answers", user: user(viewer), form_id: form.neat_id)
    item = result.value["items"].find { |entry| entry["person"]["name"] == name }
    assert item, "#{name} should have an answer in effect"
    item["answers"].map { |answer| answer["answer"] }
  end

  # A form nobody has submitted yet, so nothing but the audit history can say what
  # its questions were.
  def unsubmitted_form
    form = create_world_form("Unsubmitted", @alpha)
    form.form_questions.create!(kind: :input, key: "linked_phone", label: "Linked phone", person_field: PersonField.system_field("phone_number"), profile_mode: :prefill)
    form.form_questions.create!(kind: :input, key: "own_phone", label: "Own phone", data_type: :phone)
    form.form_questions.create!(kind: :input, key: "pick", label: "Pick", data_type: :string)
    form
  end

  def assert_no_contact_in_snapshot(form, subject, key)
    submission = form.response_for(person(subject)).active_submission
    assert submission, "the answer should be in effect"
    snapshot = submission.content["questions"].find { |entry| entry["key"] == key }
    assert_equal "string", snapshot["type"]
    assert_not_includes %w[ phone ], snapshot["person_field"]
    submission
  end

  def answers_for(name)
    result = call_tool("form_answers", user: user(:alpha_manager), form_id: @form.neat_id)
    result.value["items"].find { |item| item["person"]["name"] == name }["answers"].to_h { |answer| [ answer["question_id"], answer["answer"] ] }
  end

  # The edit changed the question, the minor's response still holds the value and
  # stays in effect, and only that answer is affected. An answer recorded under a
  # different profile field than the question's now is hidden from everyone in this
  # build (FormSubmission#answer), so an adult keeps it only if it wasn't: pass
  # adult_keeps: false for those.
  def assert_left_out_for_the_minor_only(key, adult_keeps: true)
    question = question(key)
    value = ANSWERS.fetch(key)
    response = @form.response_for(person(:ward))
    assert_equal value, response.active_submission.answers[key]
    assert_equal "complete", response.status

    ward = answers_for("Ward World")
    assert_not_includes ward.keys, question.neat_id
    assert_not_includes ward.values, value
    assert_includes ward.values, "kept"
    assert_equal(adult_keeps ? value : "", answers_for("AlphaMember World")[question.neat_id].to_s)
  end

  test "this build keeps an answered question's type, link and key, on the page and in the model" do
    linked = question("linked_phone")
    patch form_question_path(@form, linked), params: { form_question: { person_field_id: "", label: "Renamed" } }
    assert_response :see_other
    assert_equal "Renamed", linked.reload.label
    assert_not_nil linked.person_field_id

    typed = question("own_phone")
    patch form_question_path(@form, typed), params: { form_question: { data_type: "string" } }
    assert typed.reload.type_phone?

    assert_not linked.update(person_field_id: nil)
    assert_not typed.update(data_type: :string)

    delete form_question_path(@form, typed)
    assert_not Form.find(@form.id).form_questions.build(kind: :input, key: "own_phone", label: "Own phone", data_type: :string).valid?

    post form_questions_path(@form), params: { form_question: { kind: "input", label: "Own phone", data_type: "string" } }
    assert_response :redirect
    assert_nil @form.form_questions.find_by(key: "own_phone")
    added = @form.form_questions.find_by!(key: "own_phone_2")
    assert_not_includes answers_for("Ward World").values, ANSWERS.fetch("own_phone")
    assert_nil answers_for("AlphaMember World")[added.neat_id]
  end

  %w[ linked_email linked_phone linked_address linked_birthday ].each do |key|
    test "unlinking #{key} after it was answered keeps it out for a minor" do
      edit_question(key, person_field_id: "")

      assert_nil question(key).person_field_id
      assert_left_out_for_the_minor_only(key, adult_keeps: false)
    end
  end

  test "linking a typed phone question to a custom text field keeps it out for a minor" do
    edit_question("own_phone", person_field_id: @custom_text.id, profile_mode: "prefill")

    assert_equal @custom_text, question("own_phone").person_field
    assert_left_out_for_the_minor_only("own_phone")
  end

  test "moving a built-in phone link to a custom text field keeps it out for a minor" do
    edit_question("linked_phone", person_field_id: @custom_text.id, profile_mode: "prefill")

    assert_equal @custom_text, question("linked_phone").person_field
    assert_left_out_for_the_minor_only("linked_phone", adult_keeps: false)
  end

  test "removing a typed phone question and adding a text one with the same key keeps it out for a minor" do
    replace_with_plain_question(@form, "own_phone", "Own phone")

    assert question("own_phone").type_string?
    assert_left_out_for_the_minor_only("own_phone")
  end

  # A new submission starts from the last one's answers, and its own snapshot
  # holds the edited question.
  def resubmit(subject, answers: { "pick" => "kept" })
    submission = respond_to_form(Form.find(@form.id), subject, as: subject == :ward ? :guardian : subject, answers: answers)
    assert_equal 2, submission.number
    submission
  end

  def assert_carried_forward(key)
    submission = resubmit(:ward)

    assert_equal ANSWERS.fetch(key), submission.answers[key]
    assert_not_includes contact_keys_in(submission), key
    assert_left_out_for_the_minor_only(key)
  end

  def contact_keys_in(submission)
    submission.content["questions"].select { |snapshot| snapshot["type"].in?(%w[ phone email ]) || snapshot["person_field"].in?(%w[ email phone address birthday ]) }.map { |snapshot| snapshot["key"] }
  end

  test "resubmitting after unlinking built-in phone keeps it out for a minor" do
    edit_question("linked_phone", person_field_id: "")

    # Recorded under the field it's no longer linked to, so this build doesn't carry it.
    assert_nil resubmit(:ward).answers["linked_phone"]
    ward = answers_for("Ward World")
    assert_not_includes ward.values, ANSWERS.fetch("linked_phone")
    assert_includes ward.values, "kept"
  end

  test "resubmitting after linking a typed phone question to a custom text field keeps it out for a minor" do
    edit_question("own_phone", person_field_id: @custom_text.id, profile_mode: "prefill")

    assert_carried_forward("own_phone")
  end

  test "resubmitting after removing a typed phone question and adding a text one with the same key keeps it out for a minor" do
    replace_with_plain_question(@form, "own_phone", "Own phone")

    assert_carried_forward("own_phone")
  end

  test "a value entered again under a question that is now plain stays out for a minor" do
    edit_question("linked_phone", person_field_id: "")
    submission = resubmit(:ward, answers: { "linked_phone" => "not a phone" })

    assert_equal "not a phone", submission.answers["linked_phone"]
    assert_not_includes answers_for("Ward World").values, "not a phone"
  end

  test "an adult's answer isn't carried past the same edit, and stays once entered again" do
    edit_question("linked_phone", person_field_id: "")
    resubmit(:alpha_member, answers: { "pick" => "kept", "linked_phone" => "555-0199" })

    assert_equal "555-0199", answers_for("AlphaMember World")[question("linked_phone").neat_id]
  end

  test "one response's earlier submissions don't affect another's" do
    edit_question("linked_phone", person_field_id: "")
    other = create_world_form("Other", @alpha)
    other.form_questions.create!(kind: :input, key: "linked_phone", label: "Linked phone", data_type: :string)
    other.form_questions.reset
    respond_to_form(other, :ward, as: :guardian, answers: { "linked_phone" => "not contact" })

    result = call_tool("form_answers", user: user(:admin), form_id: other.neat_id, person_id: person(:ward).neat_id)
    assert_equal [ "not contact" ], result.value["items"].first["answers"].map { |answer| answer["answer"] }
  end

  test "the submissions are not loaded per row" do
    edit_question("own_phone", person_field_id: "")
    resubmit(:ward)
    resubmit(:alpha_member)
    one_minor = submission_loads
    person(:alpha_member).update!(birthday: 16.years.ago.to_date)

    assert_equal one_minor, submission_loads
    assert_not_includes answers_for("AlphaMember World").values, "555-0102"
  end

  def submission_loads
    loads = 0
    counter = ->(*, payload) { loads += 1 if payload[:sql].include?('FROM "form_submissions"') }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      call_tool("form_answers", user: user(:alpha_manager), form_id: @form.neat_id)
    end
    loads
  end

  test "an edit on a form waiting for a signature, and the resubmit it forces, keep the answer out for a minor" do
    form = unsubmitted_form
    signature = form.form_questions.create!(kind: :signature, key: "consent", label: "Consent", signer: :guardian)
    answers = { linked_phone: "555-0101", pick: "kept" }

    signed_in_as(:guardian) { save_answers(form, :ward, answers, submit: true) }
    submission = form.response_for(person(:ward)).form_submissions.sole
    assert submission.pending?
    assert_equal "phone", submission.content["questions"].find { |entry| entry["key"] == "linked_phone" }["person_field"]

    edit_question("linked_phone", form: form, person_field_id: "")
    assert submission.reload.draft?, "the edit sends it back to draft"

    signed_in_as(:guardian) do
      save_answers(form, :ward, answers, submit: true)
      post sign_form_response_path(form, person(:ward)), params: { question_id: signature.id, typed_name: "Guardian World" }
      assert_response :see_other
    end

    assert_equal submission, form.response_for(person(:ward)).form_submissions.sole, "there is still one submission"
    stored = assert_no_contact_in_snapshot(form, :ward, "linked_phone")
    assert_equal "555-0101", stored.answers["linked_phone"]
    assert_equal [ "kept" ], form_answers_values(form, "Ward World").compact
  end

  test "a draft saved before the edit keeps typed answers out for a minor, and an adult keeps them" do
    form = unsubmitted_form
    answers = { linked_phone: "555-0101", own_phone: "555-0102", pick: "kept" }
    signed_in_as(:guardian) { save_answers(form, :ward, answers) }
    signed_in_as(:alpha_member) { save_answers(form, :alpha_member, answers) }

    edit_question("linked_phone", form: form, person_field_id: "")
    edit_question("own_phone", form: form, person_field_id: @custom_text.id, profile_mode: "prefill")

    signed_in_as(:guardian) { post submit_form_response_path(form, person(:ward)) }
    signed_in_as(:alpha_member) { post submit_form_response_path(form, person(:alpha_member)) }

    stored = assert_no_contact_in_snapshot(form, :ward, "linked_phone")
    assert_equal [ "555-0101", "555-0102" ], stored.answers.values_at("linked_phone", "own_phone")
    assert_equal [ "kept" ], form_answers_values(form, "Ward World")
    assert_equal [ "555-0101", "555-0102", "kept" ], form_answers_values(form, "AlphaMember World")
  end

  test "a draft that took its number from the profile keeps it out for a minor" do
    person(:ward).update!(phone_number: "555-7777")
    form = unsubmitted_form
    signed_in_as(:guardian) { save_answers(form, :ward, { pick: "kept" }) }
    assert_equal "555-7777", form.response_for(person(:ward)).open_submission.answers["linked_phone"]

    edit_question("linked_phone", form: form, person_field_id: "")
    signed_in_as(:guardian) { post submit_form_response_path(form, person(:ward)) }

    stored = assert_no_contact_in_snapshot(form, :ward, "linked_phone")
    assert_equal "555-7777", stored.answers["linked_phone"]
    assert_equal [ "kept" ], form_answers_values(form, "Ward World")
  end

  test "a question removed and added back while a draft is open keeps the answer out for a minor" do
    form = unsubmitted_form
    signed_in_as(:guardian) { save_answers(form, :ward, { own_phone: "555-0102", pick: "kept" }) }

    replace_with_plain_question(form, "own_phone", "Own phone")

    signed_in_as(:guardian) { post submit_form_response_path(form, person(:ward)) }

    assert_equal "555-0102", form.response_for(person(:ward)).active_submission.answers["own_phone"]
    assert_not_includes form_answers_values(form, "Ward World"), "555-0102"
  end

  test "a question linked by mistake and corrected stays out for minors, and adults keep it" do
    form = unsubmitted_form
    plain = form.form_questions.create!(kind: :input, key: "shoe", label: "Shoe", data_type: :string)
    edit_question("shoe", form: form, person_field_id: PersonField.system_field("address").id, profile_mode: "prefill")
    edit_question("shoe", form: form, person_field_id: "")
    assert_nil plain.reload.person_field_id

    respond_to_form(Form.find(form.id), :ward, as: :guardian, answers: { shoe: "42", pick: "kept" })
    respond_to_form(Form.find(form.id), :alpha_member, as: :alpha_member, answers: { shoe: "42", pick: "kept" })

    assert_not_includes form_answers_values(form, "Ward World"), "42"
    assert_includes form_answers_values(form, "AlphaMember World"), "42"
  end

  test "a question's history on one form doesn't affect the same key on another" do
    form = unsubmitted_form
    edit_question("linked_phone", form: form, person_field_id: "")
    other = create_world_form("Other", @alpha)
    other.form_questions.create!(kind: :input, key: "linked_phone", label: "Linked phone", data_type: :string)
    respond_to_form(Form.find(other.id), :ward, as: :guardian, answers: { linked_phone: "not contact" })

    assert_equal [ "not contact" ], form_answers_values(other, "Ward World")
  end

  test "another form's question that only mentions this form's ID in its text doesn't count" do
    form = unsubmitted_form
    form.form_questions.create!(kind: :input, key: "shared_key", label: "Shared", data_type: :string)
    other = create_world_form("Other", @alpha)
    mention = other.form_questions.create!(kind: :input, key: "shared_key", label: "See #{form.id}", data_type: :phone)
    mention.update!(label: "Renamed")
    respond_to_form(Form.find(form.id), :ward, as: :guardian, answers: { shared_key: "x1", pick: "kept" })

    assert_includes form_answers_values(form, "Ward World"), "x1"
  end

  test "an earlier version linked to a custom phone field counts, and one to a custom text field doesn't" do
    form = unsubmitted_form
    custom_phone = PersonField.create!(name: "Custom phone", data_type: :phone, read_permission: "everyone", write_permission: "everyone")
    form.form_questions.create!(kind: :input, key: "was_phone", label: "Was phone", data_type: :string)
    form.form_questions.create!(kind: :input, key: "was_text", label: "Was text", data_type: :string)
    edit_question("was_phone", form: form, person_field_id: custom_phone.id, profile_mode: "prefill")
    edit_question("was_phone", form: form, person_field_id: "")
    edit_question("was_text", form: form, person_field_id: @custom_text.id, profile_mode: "prefill")
    edit_question("was_text", form: form, person_field_id: "")

    respond_to_form(Form.find(form.id), :ward, as: :guardian, answers: { was_phone: "x1", was_text: "x2", pick: "kept" })

    assert_equal [ "x2", "kept" ].sort, form_answers_values(form, "Ward World").compact.sort
  end

  test "an earlier link to a field since deleted can't be judged and counts as contact" do
    form = unsubmitted_form
    gone = PersonField.create!(name: "Gone", data_type: :string, read_permission: "everyone", write_permission: "everyone")
    form.form_questions.create!(kind: :input, key: "was_gone", label: "Was gone", data_type: :string)
    edit_question("was_gone", form: form, person_field_id: gone.id, profile_mode: "prefill")
    edit_question("was_gone", form: form, person_field_id: "")
    gone.update!(archived_at: Time.current)
    gone.destroy!
    assert_not PersonField.exists?(gone.id)

    respond_to_form(Form.find(form.id), :ward, as: :guardian, answers: { was_gone: "x1", pick: "kept" })

    assert_equal [ "kept" ], form_answers_values(form, "Ward World").compact
  end

  def with_captured_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end

  def assert_minor_answers_empty_adult_kept
    log = with_captured_log do
      result = call_tool("form_answers", user: user(:alpha_manager), form_id: @form.neat_id)
      assert_not result.error?
      items = result.value["items"].to_h { |item| [ item["person"]["name"], item["answers"] ] }
      assert_empty items.fetch("Ward World")
      assert_includes items.fetch("AlphaMember World").map { |answer| answer["answer"] }, "555-0102"
    end
    assert_includes log, "[MCP] form_answers can't read question history for form #{@form.id}"
  end

  test "unparsable question history leaves a minor's answers empty, keeps an adult's, and logs it" do
    AuditLog.create!(item_type: "FormQuestion", item_id: SecureRandom.uuid, event: "update", object: "form_id: #{@form.id}\nkey: [unclosed")

    assert_minor_answers_empty_adult_kept
  end

  test "question history that isn't a record leaves a minor's answers empty" do
    AuditLog.create!(item_type: "FormQuestion", item_id: SecureRandom.uuid, event: "update", object: "just #{@form.id}")

    assert_minor_answers_empty_adult_kept
  end

  test "a version with no key leaves a minor's answers empty" do
    AuditLog.create!(item_type: "FormQuestion", item_id: SecureRandom.uuid, event: "update", object: { "form_id" => @form.id, "data_type" => 7 }.to_yaml)

    assert_minor_answers_empty_adult_kept
  end

  test "an unreachable audit database leaves a minor's answers empty, keeps an adult's, and logs it" do
    AuditLog.define_singleton_method(:where) { |*| raise ActiveRecord::ConnectionNotEstablished, "audit database down" }

    assert_minor_answers_empty_adult_kept
  ensure
    AuditLog.singleton_class.remove_method(:where)
  end

  def question_history_loads
    loads = 0
    counter = ->(*, payload) { loads += 1 if payload[:sql].include?("object") && payload[:sql].include?("LIKE") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      call_tool("form_answers", user: user(:alpha_manager), form_id: @form.neat_id)
    end
    loads
  end

  test "the question history is loaded once for many minors, and not at all for adults" do
    person(:alpha_member).update!(birthday: 16.years.ago.to_date)
    assert_equal 1, question_history_loads

    person(:alpha_member).update!(birthday: Date.new(1990, 5, 6))
    person(:ward).update!(birthday: Date.new(1990, 5, 6))
    assert_equal 0, question_history_loads
  end

  test "an archived built-in field in a snapshot still counts" do
    edit_question("linked_address", person_field_id: "")
    PersonField.system_field("address").update!(archived_at: Time.current)

    assert_left_out_for_the_minor_only("linked_address", adult_keeps: false)
  end

  test "a submission without a snapshot is judged as the question is now" do
    @form.response_for(person(:ward)).active_submission.update_columns(content: {})

    ward = answers_for("Ward World")
    assert_not_includes ward.values, "555-0102"
    assert_not_includes ward.values, "555-0101"
    assert_includes ward.values, "kept"
  end

  test "the snapshots' fields are loaded once, however many minors answered" do
    edit_question("own_phone", person_field_id: "")
    person(:alpha_member).update!(birthday: 16.years.ago.to_date)
    loads = 0
    counter = ->(*, payload) { loads += 1 if payload[:sql].include?("system_source") && payload[:sql].include?("\"key\"") }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      call_tool("form_answers", user: user(:alpha_manager), form_id: @form.neat_id)
    end

    assert_equal 1, loads
  end
end
