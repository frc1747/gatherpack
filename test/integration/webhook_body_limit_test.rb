require "test_helper"

class WebhookBodyLimitTest < ActiveSupport::TestCase
  setup do
    @limit = WebhookBodyLimit.new(->(env) { [ 204, {}, [] ] })
  end

  test "an oversized webhook request is refused before it reaches the app" do
    [ "/gateways/gw_123/webhook", "/gateways/gw_123/webhook/", "/gateways/gw_123/webhook.json", "//gateways//gw_123/webhook" ].each do |path|
      assert_equal 413, call(path, "POST", GatewaysController::WEBHOOK_MAX_BYTES + 1), "#{path} reached the app"
    end
  end

  test "webhook requests within the limit and other requests pass through" do
    assert_equal 204, call("/gateways/gw_123/webhook", "POST", 100)
    assert_equal 204, call("/ledger_entries/1", "POST", GatewaysController::WEBHOOK_MAX_BYTES + 1)
    assert_equal 204, call("/gateways/gw_123/webhook", "GET", GatewaysController::WEBHOOK_MAX_BYTES + 1)
  end

  test "a request to an oversized webhook with a format suffix gets 413 through the whole stack" do
    gateway = gateway_stripe_gateways(:with_secret)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.host! "localhost"

    session.post "/gateways/#{gateway.to_param}/webhook.json", params: "x" * (GatewaysController::WEBHOOK_MAX_BYTES + 1), headers: { "CONTENT_TYPE" => "application/json" }

    assert_equal 413, session.response.status
  end

  private
    def call(path, method, length)
      env = Rack::MockRequest.env_for("/", method: method, "CONTENT_LENGTH" => length.to_s)
      env["PATH_INFO"] = path
      @limit.call(env).first
    end
end
