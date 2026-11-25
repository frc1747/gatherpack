require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# "A guardian, or the person once of age" goes by the birthday on file, and
# someone on the child side of a guardianship link can't change their own
# birthday: not on their profile, and not through a form that updates the
# profile. A form's Birthday answer reaches the profile only from someone
# allowed to write it.
class FormBirthdayConsentTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  TWELVE = Date.current - 12.years

  setup do
    host! "localhost"
    build_person_fields_world
    PersonField.ensure_system_fields!
    @birthday = PersonField.system_field("birthday")
    person(:a1).update!(birthday: TWELVE)
  end

  def trip(birthday_question: false, required: false)
    form = create_world_form("Trip", team: @den_a, include: [ @den_a ])
    add_choice(form, "Bus seat", [ "Front", "Back" ])
    add_profile_question(form, @birthday, :update_profile, required: required) if birthday_question
    @consent = add_signature(form, "Permission to travel", signer: "guardian_if_minor")
    form
  end

  def signers(form)
    form.response_for(person(:a1)).reload.form_submissions.flat_map(&:form_signatures).map(&:signer)
  end

  test "a minor can't sign their own guardian consent by changing their birthday" do
    with_settings(feature_forms: "true") do
      form = trip
      respond(form, :a1, as: :a1, answers: { "bus_seat" => "Front" })
      assert_not FormAccess.new(person(:a1), person(:a1), form).can_sign?(@consent)

      sign_in person(:a1).user
      patch person_path(person(:a1)), params: { person: { person_field_values: { birthday: "2000-01-01" } } }
      post sign_form_response_path(form, person(:a1)), params: { question_id: @consent.id, typed_name: "A1 World" }

      assert_not_includes signers(form), person(:a1)
      assert_equal TWELVE, person(:a1).reload.birthday
    end
  end

  test "a minor can't change their birthday through a form that updates the profile" do
    with_settings(feature_forms: "true") do
      form = trip(birthday_question: true)
      sign_in person(:a1).user
      get edit_form_response_path(form, person(:a1))
      assert_select "input[name=?]", "form_response[answers][birthday]", count: 0

      patch form_response_path(form, person(:a1)), params: { submit: "1", form_response: { answers: { bus_seat: "Front", birthday: "2000-01-01" } } }
      submission = form.response_for(person(:a1)).open_submission
      assert_equal TWELVE.iso8601, submission.answers["birthday"], "the answer stays the profile's"
      post sign_form_response_path(form, person(:a1)), params: { question_id: @consent.id, typed_name: "A1 World" }

      assert_equal TWELVE, person(:a1).reload.birthday
      assert_not_includes signers(form), person(:a1)
    end
  end

  test "a guardian's Birthday answer submitted by the ward isn't written to the profile" do
    @birthday.update!(read_permission: "family", write_permission: "family")
    with_settings(feature_forms: "true") do
      form = trip(birthday_question: true)
      sign_in person(:parent_a1).user
      patch form_response_path(form, person(:a1)), params: { form_response: { answers: { birthday: "2000-01-01" } } }
      sign_out :user

      sign_in person(:a1).user
      patch form_response_path(form, person(:a1)), params: { submit: "1", form_response: { answers: { bus_seat: "Front" } } }
      submission = form.response_for(person(:a1)).open_submission
      sign_out :user
      sign(form, :a1, as: :parent_a1)

      assert submission.reload.active?
      assert_equal TWELVE, person(:a1).reload.birthday
      assert_includes submission.profile_skipped, "birthday"
    end
  end

  test "a guardian who may write the birthday updates it through the form" do
    @birthday.update!(read_permission: "family", write_permission: "family")
    with_settings(feature_forms: "true") do
      form = trip(birthday_question: true)
      sign_in person(:parent_a1).user
      patch form_response_path(form, person(:a1)), params: { submit: "1", form_response: { answers: { bus_seat: "Front", birthday: "2013-03-04" } } }
      sign(form, :a1, as: :parent_a1)

      assert_equal Date.new(2013, 3, 4), person(:a1).reload.birthday
      assert form.response_for(person(:a1)).complete?
    end
  end

  test "on the default Birthday level a guardian can't answer it, and a leader can" do
    with_settings(feature_forms: "true") do
      form = trip(birthday_question: true, required: true)
      person(:a1).update!(birthday: nil)

      sign_in person(:parent_a1).user
      patch form_response_path(form, person(:a1)), params: { submit: "1", form_response: { answers: { bus_seat: "Front", birthday: "2000-01-01" } } }
      submission = form.response_for(person(:a1)).open_submission
      assert_nil submission.answers["birthday"]
      assert_includes submission.waiting_for, "an answer to Birthday"
      sign_out :user

      sign_in person(:den_a_leader).user
      patch form_response_path(form, person(:a1)), params: { submit: "1", form_response: { answers: { birthday: "2013-03-04" } } }
      sign_out :user
      sign(form, :a1, as: :parent_a1)

      assert_equal Date.new(2013, 3, 4), person(:a1).reload.birthday
      assert form.response_for(person(:a1)).complete?
    end
  end
end
