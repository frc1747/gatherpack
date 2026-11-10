require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# Withdrawing a response changes it, so it follows the form's rules for
# updating: open (or closed with late entry for leaders), and "Allow
# updates". Leaders may still withdraw at any time, to fix a mistake.
class FormWithdrawTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
  end

  def trip(**attributes)
    form = create_world_form("Trip", team: @den_a, include: [ @den_a ], **attributes)
    add_choice(form, "Bus seat", [ "Front", "Back" ])
    respond(form, :a1, as: :a1, answers: { "bus_seat" => "Front" })
    form
  end

  test "a respondent can't withdraw and resubmit on a form that doesn't allow updates" do
    with_settings(feature_forms: "true") do
      form = trip(allow_updates: false)
      as(:a1) do
        get edit_form_response_path(form, person(:a1))
        assert_redirected_to root_path, "updating directly is refused"

        post withdraw_form_response_path(form, person(:a1))
        patch form_response_path(form, person(:a1)), params: { submit: "1", form_response: { answers: { bus_seat: "Back" } } }
        active = form.response_for(person(:a1)).reload.active_submission
        assert_equal "Front", active&.answers&.dig("bus_seat")

        get form_response_path(form, person(:a1))
        assert_select "button", text: "Withdraw response", count: 0
      end
    end
  end

  test "a respondent can't withdraw a complete response after the form closes" do
    with_settings(feature_forms: "true") do
      form = trip
      form.update!(status: :closed)
      as(:a1) do
        post withdraw_form_response_path(form, person(:a1))
        assert form.response_for(person(:a1)).reload.complete?

        get form_response_path(form, person(:a1))
        assert_select "button", text: "Withdraw response", count: 0
      end
    end
  end

  test "a respondent withdraws on an open form that allows updates" do
    with_settings(feature_forms: "true") do
      form = trip
      as(:a1) do
        get form_response_path(form, person(:a1))
        assert_select "button", text: "Withdraw response"
        post withdraw_form_response_path(form, person(:a1))
      end
      assert form.response_for(person(:a1)).reload.withdrawn?
    end
  end

  test "a leader withdraws after the form closes and on a form that doesn't allow updates" do
    with_settings(feature_forms: "true") do
      closed = trip
      closed.update!(status: :closed)
      no_updates = create_world_form("Campout", team: @den_a, include: [ @den_a ], allow_updates: false)
      add_choice(no_updates, "Tent", [ "Big", "Small" ])
      respond(no_updates, :a1, as: :a1, answers: { "tent" => "Big" })

      as(:den_a_leader) do
        get form_response_path(closed, person(:a1))
        assert_select "button", text: "Withdraw response"
        post withdraw_form_response_path(closed, person(:a1))
        post withdraw_form_response_path(no_updates, person(:a1))
      end
      assert closed.response_for(person(:a1)).reload.withdrawn?
      assert no_updates.response_for(person(:a1)).reload.withdrawn?
    end
  end

  test "a teammate the respond level reaches follows the same rules" do
    with_settings(feature_forms: "true") do
      form = trip(respond: "team", read: "team")
      form.update!(status: :closed)
      as(:a2) do
        post withdraw_form_response_path(form, person(:a1))
        assert form.response_for(person(:a1)).reload.complete?, "not once the form has closed"
      end

      form.update!(status: :open)
      as(:a2) do
        post withdraw_form_response_path(form, person(:a1))
        assert form.response_for(person(:a1)).reload.withdrawn?, "while they may update it, they may withdraw it"
      end
    end
  end

  private

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
