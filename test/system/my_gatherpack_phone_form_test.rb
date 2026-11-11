require "application_system_test_case"
require "my_gatherpack_test_helper"
require_relative "../support/forms_world"

class MyGatherpackPhoneFormSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include MyGatherpackTestHelper
  include FormsWorld

  # The form is found by its Rails ids, as the stylesheet does.
  FORM = ":is(form[id^='new_form_response'], form[id^='edit_form_response'])".freeze
  BAR = "#{FORM} .card-footer".freeze

  # config.hosts allows localhost in test, but not Capybara's 127.0.0.1.
  setup do
    @saved_app_host = Capybara.app_host
    @saved_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    turn_on_my_gatherpack
    Settings[:feature_forms] = "true"
    page.driver.browser.manage.window.resize_to(390, 844)
    build_person_fields_world
    build_form
  end

  teardown do
    # The browser is shared with other system tests.
    page.driver.browser.manage.window.resize_to(1400, 1400)
    restore_my_gatherpack
    Capybara.app_host = @saved_app_host
    Capybara.always_include_port = @saved_include_port
  end

  test "at 390 px a member fills out every kind of question and the answers are saved" do
    sign_in person(:a1).user
    visit edit_form_response_path(@form, person(:a1))

    assert_selector FORM
    assert_no_sideways_scroll
    within(BAR) { assert_button "Submit" }
    assert_text "Section heading"
    assert_text "Read this first"
    assert_text "Signed after submitting"
    # A yes/no question with a description keeps its label readable.
    assert_operator evaluate_script("document.querySelector('label[for=form_question_#{@pledge.key}]').getBoundingClientRect().width"), :>, 100

    # An unticked acknowledgment shows its message, and the other answers stay put.
    fill_in_form(skip_ack: true)
    click_button "Submit"
    assert_text "Please check the answers marked below."
    assert_selector ".invalid-feedback", text: /\S/
    assert_equal "Likes pasta", find("#form_question_#{@notes.key}").value
    assert_no_sideways_scroll

    check "form_question_#{@ack.key}"
    click_button "Submit"
    # Saving finished: the page moved on to the response.
    assert_current_path form_response_path(@form, person(:a1))
    assert_no_selector FORM

    assert_saved

    # Signing is still possible on a phone, and finishes.
    fill_in "typed_name_#{@consent.key}", with: "A1 World"
    click_button "Sign"
    assert_no_selector "#sign_#{@consent.key}"
    assert_equal 1, @form.response_for(person(:a1)).reload.active_submission.standing_signatures.count
  end

  test "the Save bar is opaque and stays above the tab bar, after a full load and a Turbo visit" do
    sign_in person(:a1).user

    # A full load, then a Turbo visit from the Forms page.
    visit edit_form_response_path(@form, person(:a1))
    assert_bar_pinned
    visit forms_path
    click_link "Trip Details"
    assert_selector FORM
    assert_bar_pinned
  end

  test "Discard is a large control" do
    sign_in person(:a1).user
    visit edit_form_response_path(@form, person(:a1))
    fill_in "form_question_#{@name.key}", with: "Pat Smith"
    click_button "Save for later"
    assert_text "Your answers were saved"
    visit edit_form_response_path(@form, person(:a1))

    assert_button "Discard this draft"
    assert_operator evaluate_script("document.querySelector(\"form[action$='/discard'] .btn\").getBoundingClientRect().height"), :>=, 44

    # The response page posts to the same route, and keeps its own small button.
    visit form_response_path(@form, person(:a1))
    assert_button "Discard draft"
    assert_operator evaluate_script("document.querySelector(\"form[action$='/discard'] .btn\").getBoundingClientRect().height"), :<, 44
  end

  test "with the flag off the original form still saves, with no phone styling" do
    Settings[:feature_my_gatherpack] = "false"
    sign_in person(:a1).user
    visit edit_form_response_path(@form, person(:a1))

    assert_selector FORM
    assert_no_selector ".phone-tabs"
    assert_operator evaluate_script("document.querySelector('.card-footer').getBoundingClientRect().height"), :<, 60
    assert_equal "static", evaluate_script("getComputedStyle(document.querySelector('.card-footer')).position")
    fill_in_form
    click_button "Submit"
    assert_current_path form_response_path(@form, person(:a1))

    assert_saved
  end

  test "at desktop width the form has the original layout" do
    page.driver.browser.manage.window.resize_to(1400, 900)
    sign_in person(:a1).user
    visit edit_form_response_path(@form, person(:a1))

    assert_equal "static", evaluate_script("getComputedStyle(document.querySelector('.card-footer')).position")
    assert_operator evaluate_script("document.querySelector('#form_question_#{@name.key}').getBoundingClientRect().height"), :<, 44
  end

  private

  def build_form
    @form = create_world_form("Trip Details")
    @form.form_questions.create!(kind: :heading, label: "Section heading")
    @form.form_questions.create!(kind: :statement, body: "Read this first")
    @name = @form.form_questions.create!(kind: :input, label: "Full name", data_type: :string, required: true)
    @notes = @form.form_questions.create!(kind: :input, label: "Notes", data_type: :text)
    @count = @form.form_questions.create!(kind: :input, label: "Guests", data_type: :integer)
    @date = @form.form_questions.create!(kind: :input, label: "Arrival", data_type: :date)
    @phone = @form.form_questions.create!(kind: :input, label: "Phone", data_type: :phone)
    @email = @form.form_questions.create!(kind: :input, label: "Email", data_type: :email)
    @lunch = add_choice(@form, "Lunch", %w[ Pasta Salad ])
    @extras = @form.form_questions.create!(kind: :input, label: "Extras", data_type: :multi_select, choices: %w[ Water Snack Coat ])
    @pledge = @form.form_questions.create!(kind: :input, label: "Pledge", data_type: :boolean, body: "Tick if you agree to bring your own water")
    @intent = @form.form_questions.create!(kind: :intent, label: "Are you coming?")
    @ack = @form.form_questions.create!(kind: :acknowledgment, label: "I have read the rules", required: true)
    @consent = add_signature(@form, "Consent", signer: "subject")
  end

  def fill_in_form(skip_name: false, skip_ack: false)
    fill_in "form_question_#{@name.key}", with: "Pat Smith" unless skip_name
    fill_in "form_question_#{@notes.key}", with: "Likes pasta"
    fill_in "form_question_#{@count.key}", with: "3"
    execute_script("const d = document.getElementById('form_question_#{@date.key}'); d.value = '2030-05-17'; d.dispatchEvent(new Event('input', { bubbles: true }))")
    fill_in "form_question_#{@phone.key}", with: "555-0100"
    fill_in "form_question_#{@email.key}", with: "pat@example.com"
    select "Salad", from: "form_question_#{@lunch.key}"
    check "Snack"
    check "Coat"
    choose "Yes"
    check "form_question_#{@pledge.key}"
    check "form_question_#{@ack.key}" unless skip_ack
  end

  # The off-canvas menu waits off-screen to the right, so it's left out: what
  # matters is that the page itself can't scroll sideways and the form fits.
  def assert_no_sideways_scroll
    wide = evaluate_script("[...document.querySelectorAll('body *')].filter(e => !e.closest('.offcanvas-md, .phone-tabs') && e.getBoundingClientRect().right > document.documentElement.clientWidth + 1).map(e => e.tagName + '.' + e.className + ':' + Math.round(e.getBoundingClientRect().right))")
    assert_empty wide, "wider than the screen"
    execute_script("window.scrollTo(100, window.scrollY)")
    assert_equal 0, evaluate_script("window.scrollX"), "page scrolls sideways"
  end

  def assert_bar_pinned
    bar = evaluate_script("document.querySelector(\"#{BAR}\").getBoundingClientRect().toJSON()")
    tabs = evaluate_script("document.querySelector('.phone-tabs').getBoundingClientRect().top")
    # Sticky: just above the tab bar on load, not at the end of the long form, and not see-through.
    assert_operator bar["bottom"], :<=, tabs + 0.5
    assert_operator bar["bottom"], :>=, tabs - 4
    assert_equal 1.0, evaluate_script("(c => c.match(/rgba/) ? parseFloat(c.split(',')[3]) : 1)(getComputedStyle(document.querySelector(\"#{BAR}\")).backgroundColor)")
    assert evaluate_script("[...document.querySelectorAll(\"#{FORM} .form-control, #{FORM} .form-select, #{BAR} .btn\")].every(e => e.getBoundingClientRect().height >= 44)")
    assert_equal 12, evaluate_script("parseFloat(getComputedStyle(document.querySelector(\"#{BAR}\")).paddingTop)")
  end

  def assert_saved
    answers = @form.response_for(person(:a1)).reload.open_submission.answers
    assert_equal "Pat Smith", answers[@name.key]
    assert_equal "Likes pasta", answers[@notes.key]
    assert_equal 3, answers[@count.key].to_i
    assert_equal "2030-05-17", answers[@date.key]
    assert_equal "555-0100", answers[@phone.key]
    assert_equal "pat@example.com", answers[@email.key]
    assert_equal "Salad", answers[@lunch.key]
    assert_equal %w[ Coat Snack ], Array(answers[@extras.key]).sort
    assert_equal "Yes", answers[@intent.key]
    assert_equal true, answers[@pledge.key]
    assert_equal true, answers[@ack.key]
  end
end
