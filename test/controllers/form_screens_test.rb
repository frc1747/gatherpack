require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# The Forms screens follow the screen standard: one job button per record,
# the rest after it or in More, Cancel before a form's main button, and the
# breadcrumb as the way back.
class FormScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper
  include FormsWorld
  include SettingsTestHelper

  ROW = ".screen-action-row".freeze
  BUTTONS = "#{ROW} > a.btn, #{ROW} > form .btn".freeze
  ACTIONS = "#{BUTTONS}, #{ROW} .dropdown-menu li:not(.d-md-none)".freeze

  setup do
    host! "localhost"
    build_person_fields_world
    @form = create_world_form
    add_choice(@form, "Sandwich", [ "Slim 1", "Slim 4", "Big John" ])
  end

  test "a response page shows the one job button for each state" do
    with_feature do
      as(:a1) do
        get form_response_path(@form, person(:a1))
        assert_job "Fill in"
      end

      respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4" }, submit: false)
      as(:a1) do
        get form_response_path(@form, person(:a1))
        assert_job "Continue"
        assert_equal "Discard draft", action_labels.last
        assert_select "#{ROW} form[data-turbo-confirm] button", text: "Discard draft"
      end

      @form.form_responses.find_by(subject: person(:a1)).open_submission.submit!(person(:a1), FormAccess.new(person(:a1), person(:a1), @form))
      as(:a1) do
        get form_response_path(@form, person(:a1))
        assert_job "Update answers"
      end

      respond(@form, :a1, as: :a1, answers: { "sandwich" => "Big John" }, submit: false)
      as(:a1) do
        get form_response_path(@form, person(:a1))
        assert_job "Continue update"
        assert_equal "Discard update", action_labels.last
        assert_select ".alert a.btn-sm", text: "Continue update"
        assert_select ".alert button", count: 0, msg: "Discard update moved to the action row"
        assert_select "a", text: "All responses", count: 0
      end
    end
  end

  test "a response waiting for a signature offers Review answers as its job" do
    add_signature(@form)
    respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4" })
    with_feature do
      as(:a1) do
        get form_response_path(@form, person(:a1))
        assert_job "Review answers"
      end
    end
  end

  test "Withdraw comes last and keeps its confirm" do
    respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4" })
    with_feature do
      as(:pack_leader) do
        get form_response_path(@form, person(:a1))
        assert_job "Update answers"
        assert_equal "Withdraw response", action_labels.last
        assert_select "#{ROW} form[data-turbo-confirm^='Withdraw A1'] button", text: "Withdraw response"
        assert_select "a", text: "All responses", count: 0, msg: "the breadcrumb leads back to the form"
        assert_select ".border-danger", count: 0
      end
    end
  end

  test "a shared-totals viewer gets See totals after the job, and no answers" do
    @form.update!(totals_visibility: :audience)
    respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4" })
    with_feature do
      as(:a2) do
        get form_response_path(@form, person(:a2))
        assert_job "Fill in"
        assert_equal [ "Fill in", "See totals" ], action_labels
        assert_select "#{ROW} a.btn-secondary[href=?]", tally_form_path(@form), text: "See totals"
        assert_no_match "A1 World", response.body
        assert_no_match "Slim 4", response.body
      end
    end
  end

  test "the response edit page has Cancel, Save for later, then Submit, and no Discard" do
    respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4" }, submit: false)
    with_feature do
      as(:a1) do
        get edit_form_response_path(@form, person(:a1))
        labels = button_labels(".card-footer .btn")
        assert_equal [ "Cancel", "Save for later", "Submit" ], labels
        assert_select ".card-footer a.btn-secondary[href=?]", form_response_path(@form, person(:a1)), text: "Cancel"
        assert_select ".card-footer .btn-primary[value=Submit]"
        assert_select "button", text: /Discard/, count: 0
        assert_select "a", text: "Back", count: 0
      end
    end
  end

  test "a submitted version has no Back button" do
    submission = respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4" })
    with_feature do
      as(:a1) do
        get form_response_submission_path(@form, person(:a1), submission)
        assert_response :success
        assert_select "a", text: "Back", count: 0
      end
    end
  end

  test "the reminder page: Cancel, Update preview, then Send, which sends" do
    with_feature do
      as(:pack_leader) do
        get reminder_form_path(@form, team_id: @den_a.id)
        labels = button_labels(".card-footer .btn")
        assert_equal [ "Cancel", "Update preview", "Send" ], labels
        assert_select ".card-footer a.btn-secondary[href=?]", form_path(@form, team_id: @den_a.id), text: "Cancel"
        assert_select ".card-footer button.btn-secondary[name=preview]", text: "Update preview"
        assert_select ".card-footer button.btn-primary", text: "Send"
        assert_select ".btn-warning", count: 0

        assert_no_difference -> { FormReminder.count } do
          post remind_form_path(@form), params: { team_id: @den_a.id, include_guardians: "0", preview: "1" }
        end
        assert_response :unprocessable_content
        assert_select "h1", text: /Remind: Meal Choices/

        assert_difference -> { FormReminder.count }, 1 do
          post remind_form_path(@form), params: { team_id: @den_a.id, include_guardians: "0" }
        end
        assert_redirected_to form_path(@form, team_id: @den_a.id)
      end
    end
  end

  test "the edit tabs end in Cancel then Save" do
    with_feature do
      as(:pack_leader) do
        %w[ details permissions responses ].each do |tab|
          get edit_form_path(@form, tab: tab)
          labels = button_labels(".card-footer .btn")
          assert_equal [ "Cancel", "Save" ], labels.last(2), "on the #{tab} tab"
          assert_select ".card-footer a.btn-secondary[href=?]", form_path(@form), text: "Cancel"
          assert_select "a", text: "Back", count: 0
        end
      end
    end
  end

  test "with badges off, the edit page notes the ignored badge settings under the tabs" do
    @form.update!(audience_badge: @health_officer_badge)
    with_settings(feature_forms: "true", feature_badges: "false") do
      as(:admin) do
        get edit_form_path(@form)
        assert_select ".card-header ~ #badges-off .screen-state-line", text: /Badges are turned off, so this form's badge settings \(badge filter\) are ignored/
        assert_select ".alert", count: 0
      end
    end
  end

  test "question rows use outline buttons, and the question pages Cancel in grey" do
    question = @form.form_questions.first
    with_feature do
      as(:pack_leader) do
        get edit_form_path(@form, tab: "questions")
        assert_select "##{dom_id question} button.btn-sm.btn-outline-secondary[title='Move up']"
        assert_select "##{dom_id question} button.btn-sm.btn-outline-danger", text: "Remove"
        assert_select "##{dom_id question} .btn-light, ##{dom_id question} .btn-danger", count: 0

        get edit_form_question_path(@form, question)
        assert_select ".card-footer a.btn-secondary", text: "Cancel"
        get new_form_question_path(@form, kind: "heading")
        assert_select ".card-footer a.btn-secondary", text: "Cancel"
      end
    end
  end

  test "the forms list has one Printable list, in More, and New Form only for creators" do
    with_feature do
      as(:pack_leader) do
        get forms_path
        assert_select "a[href=?]", print_list_forms_path, count: 1
        assert_select ".dropdown-menu a.dropdown-item[href=?]", print_list_forms_path, text: "Printable list"
        assert_select "a.btn-success[href=?]", new_form_path, text: "New Form"
        assert_select "#form_search input[type=submit][value=Search]"
        assert_select "#form_search a.btn-dark[href=?]", forms_path, text: "Clear Search"

        get forms_path(q: { title_i_cont: "Nothing like it" })
        assert_select "##{dom_id @form}", count: 0
        assert_select "#managed_forms", text: /No forms match/
        get forms_path(q: { title_i_cont: "meal" })
        assert_select "##{dom_id @form}"
      end

      @form.form_badge_grants.create!(badge: @health_officer_badge, access: :read)
      as(:health_officer) do
        get forms_path
        assert_select "a", text: "New Form", count: 0
        assert_select "a[href=?]", print_list_forms_path, count: 1
        assert_select ".dropdown-menu a.dropdown-item[href=?]", print_list_forms_path, text: "Printable list"
      end
    end
  end

  test "the form page's filter bar keeps column choices in the pills but not as hidden copies" do
    sandwich = @form.form_questions.first
    note = @form.form_questions.create!(kind: :input, label: "Note", data_type: :string)
    with_feature do
      as(:pack_leader) do
        get form_path(@form, columns_for: @form.id, question_ids: [ note.id ], totals: "hidden")
        assert_select "#form-options input[type=hidden][name='question_ids[]']", 0, "Show sends only the ticked boxes"
        assert_select "#form-options input[type=checkbox][name='question_ids[]'][value=?][checked]", note.id
        assert_select "#form-options input[type=checkbox][name='question_ids[]'][value=?]:not([checked])", sandwich.id
        assert_select "#form-options input[type=hidden][name=totals][value=hidden]"
        assert_select "#form-options input[type=submit][value=Show]", 1, "one Show applies the team and More choices alike"
        all = css_select(".screen-filter-pills a").first
        assert_equal [ note.id ], Rack::Utils.parse_nested_query(all["href"].split("?").last)["question_ids"]
        assert_select ".screen-table-actions input[type=radio][name=layout][form=form-options]", 2
        assert_select ".screen-table-actions button.btn-dark[type=button][data-action='form-results#print']", text: "Print"
        assert_select ".screen-table-actions a.btn-secondary", text: "Download CSV"
        assert_select "#responses.table-responsive[data-form-results-target=table] table.table-sm"
      end
    end
  end

  test "the preview and audience pages have no Back button" do
    with_feature do
      as(:pack_leader) do
        get preview_form_path(@form, preview: { viewer_id: person(:pack_leader).id, subject_id: person(:a1).id })
        assert_select ".table-responsive table"
        assert_select "a", text: "Back", count: 0

        get audience_form_path(@form)
        assert_response :success
        assert_select "a", text: "Back", count: 0
      end
    end
  end

  private

  def assert_job(label)
    primary = "#{ROW} > a.btn-primary, #{ROW} > form .btn-primary"
    assert_select primary, count: 1
    assert_select primary, text: label
    assert_equal label, action_labels.first
  end

  def button_labels(selector)
    css_select(selector).map { |button| button.text.strip.presence || button["value"] }
  end

  def action_labels
    css_select(ACTIONS).map { |action| action.text.strip }
  end

  def with_feature(&block)
    with_settings(feature_forms: "true", &block)
  end

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
