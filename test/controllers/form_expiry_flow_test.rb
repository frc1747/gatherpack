require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# Setting a form's expiry, and what an expired response looks like.
class FormExpiryFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    travel_to Time.zone.local(2026, 6, 15, 10)
    build_person_fields_world
    @form = create_world_form("Physical")
    add_choice(@form, "Cleared", %w[ Yes No ])
    respond(@form, :a1, as: :a1, answers: { "cleared" => "Yes" })
  end

  test "the details tab sets when responses expire" do
    with_feature do
      as(:admin) do
        get edit_form_path(@form, tab: "details")
        assert_select "#form_expiry input[type=radio][value=never][checked]"

        patch form_path(@form), params: { tab: "details", form: { expiry: "months", expires_on: "", valid_for_months: "12" } }
        assert_redirected_to edit_form_path(@form, tab: "details")
        assert_equal [ nil, 12 ], [ @form.reload.expires_on, @form.valid_for_months ]

        patch form_path(@form), params: { tab: "details", form: { expiry: "date", expires_on: "", valid_for_months: "12" } }
        assert_response :unprocessable_entity
        assert_select "#form_expiry .text-danger", text: "Date can't be blank"
      end
    end
  end

  test "a response shows how long it's good for, and asks again once expired" do
    @form.update!(valid_for_months: 12)
    with_feature do
      as(:a1) do
        get form_response_path(@form, person(:a1))
        assert_match "Good until June 15, 2027", response.body
        assert_no_match "has expired", response.body

        travel 13.months
        FormExpiryJob.perform_now

        get form_response_path(@form, person(:a1))
        assert_match "Expired June 15, 2027", response.body
        assert_select ".alert-warning", text: /This has expired\. Please review the answers and sign again\./

        get edit_form_response_path(@form, person(:a1))
        assert_select ".alert-warning", text: /This has expired\. Please review the answers and sign again\./
      end
    end
  end

  private

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
