require "test_helper"
require_relative "../support/signup_credit_world"

# Sign-up sources on a commitment's setup page: they're listed, and can be
# added, under What counts.
class SignupCreditSourcesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupCreditWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-05 12:00")
    build_signup_credit_world
    @commitment = create_world_commitment
    @sheet_source = @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    @position_source = @commitment.commitment_sources.create!(kind: "signup_positions", subject: @cashier)
  end

  test "sign-up sources appear under What counts, with buttons to add more" do
    sign_in person(:admin).user

    with_settings(feature_commitments: "true", feature_signups: "true") do
      get edit_commitment_path(@commitment, tab: "sources")
      assert_response :success
      assert_select "#sources h3", text: "What counts"
      assert_select "#sources li##{ActionView::RecordIdentifier.dom_id(@sheet_source)}", text: /Snack Stand/
      assert_select "#sources li##{ActionView::RecordIdentifier.dom_id(@position_source)}", text: /Cashier/
      [ "signups", "signup_positions" ].each do |kind|
        assert_select "#sources a[href=?]", new_commitment_commitment_source_path(@commitment, kind: kind)
        get new_commitment_commitment_source_path(@commitment, kind: kind)
        assert_response :success
        get edit_commitment_path(@commitment, tab: "sources")
      end
    end
  end
end
