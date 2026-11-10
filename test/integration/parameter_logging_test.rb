require "test_helper"

class ParameterLoggingTest < ActiveSupport::TestCase
  setup { @filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  test "kiosk and token card values are filtered from logs" do
    scan = @filter.filter("time_kiosk" => { "tool" => "find_token", "token_value" => "8675309" })
    mint = @filter.filter("token" => { "value" => "8675309", "tokenable_nid" => "per_x" })

    assert_not_equal "8675309", scan.dig("time_kiosk", "token_value"), "kiosk scans log the card value in clear"
    assert_equal "find_token", scan.dig("time_kiosk", "tool")
    assert_not_equal "8675309", mint["token"].is_a?(Hash) ? mint.dig("token", "value") : mint["token"], "/tokens logs the card value in clear"
  end

  test "gateway API tokens are filtered from logs" do
    logged = @filter.filter("gateway" => { "name" => "Postmark", "api_token" => "pm-live-api-token", "server_token" => "pm-live-server-token" })

    assert_equal "[FILTERED]", logged["gateway"]["api_token"], "gateway[api_token] is logged in plain text (no :token in filter_parameters)"
    assert_equal "[FILTERED]", logged["gateway"]["server_token"], "gateway[server_token] is logged in plain text (no :token in filter_parameters)"
    assert_equal "Postmark", logged["gateway"]["name"]
  end

  test "OAuth tokens and card security codes are filtered from logs" do
    params = {
      "grant_type" => "refresh_token", "refresh_token" => "rt-secret", "code" => "authcode-secret",
      "token" => "access-secret", "code_verifier" => "pkce-verifier-secret", "cvv" => "123", "cvc" => "456"
    }
    filtered = @filter.filter(params)
    leaked = filtered.except("grant_type").reject { |_, value| value == "[FILTERED]" }

    assert_empty leaked, "These parameters would be logged in clear: #{leaked.keys.join(', ')}"
    assert_equal "refresh_token", filtered["grant_type"]
  end
end
