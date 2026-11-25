require "test_helper"
require_relative "../support/email_log_test_helper"

class GatewayWebhookEventsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include EmailLogTestHelper

  setup do
    @architect = users(:one)
    @architect.update!(architect: true)
    @gateway = resend_gateway
  end

  test "the gateway page links to the confirm page, which updates the webhook" do
    sign_in @architect

    get gateway_url(@gateway)
    assert_select "a[href=?]", gateway_webhook_events_path(@gateway), text: "Update webhook events"

    get gateway_webhook_events_url(@gateway)
    assert_response :success
    assert_select "h1", "Update webhook events"

    updated = false
    url = webhook_gateway_url(@gateway)
    stubbing(Resend::Webhooks, :list, ->(_params = {}) { { data: [ { "id" => "wh_1", "endpoint" => url } ] } }) do
      stubbing(Resend::Webhooks, :update, ->(_params = {}) { updated = true }) do
        post gateway_webhook_events_url(@gateway)
      end
    end

    assert updated
    assert_redirected_to gateway_path(@gateway)
  end

  test "a refusal from the service is shown on the gateway page" do
    sign_in @architect

    stubbing(Resend::Webhooks, :list, ->(_params = {}) { raise Resend::Error, "API key is restricted" }) do
      post gateway_webhook_events_url(@gateway)
    end

    assert_redirected_to gateway_path(@gateway)
    assert_match "API key is restricted", flash[:alert]
  end

  test "people who can't change gateways are turned away" do
    sign_in users(:two)

    post gateway_webhook_events_url(@gateway)

    assert_redirected_to root_path
  end

  test "hidden when the feature is off" do
    turn_off_email_log
    sign_in @architect

    get gateway_url(@gateway)
    assert_select "a[href=?]", gateway_webhook_events_path(@gateway), count: 0

    get gateway_webhook_events_url(@gateway)
    assert_redirected_to root_path
  end
end
