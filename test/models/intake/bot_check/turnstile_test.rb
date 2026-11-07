require "test_helper"
require_relative "../../../support/settings_test_helper"
require_relative "../../../support/turnstile_stub"

class Intake::BotCheck::TurnstileTest < ActiveSupport::TestCase
  include SettingsTestHelper
  include TurnstileStub

  Request = Struct.new(:remote_ip)

  setup do
    @adapter = Intake::BotCheck::Turnstile.new
    @request = Request.new("203.0.113.9")
    @params = { "cf-turnstile-response" => "token-123" }
    @keys = { intake_turnstile_site_key: "site-key", intake_turnstile_secret: "s3cret" }
  end

  def with_response(result, &block)
    stub_turnstile(@adapter, result, &block)
  end

  test "blank keys turn it off: no widget, everything passes" do
    with_settings(intake_turnstile_site_key: "", intake_turnstile_secret: "") do
      assert_nil @adapter.partial
      assert_equal "No bot check", @adapter.name
      assert @adapter.passed?({}, @request)
    end
  end

  test "one key alone leaves it off" do
    with_settings(intake_turnstile_site_key: "site-key", intake_turnstile_secret: "") do
      assert_nil @adapter.partial
      assert @adapter.passed?({}, @request)
    end
  end

  test "with both keys it shows the widget" do
    with_settings(@keys) do
      assert_equal "intake/bot_check/turnstile", @adapter.partial
      assert_equal "Cloudflare Turnstile", @adapter.name
    end
  end

  test "passes when Cloudflare says success, sending the secret, token and address" do
    with_settings(@keys) do
      with_response('{"success":true}') do |sent|
        assert @adapter.passed?(@params, @request)
        assert_equal [ { secret: "s3cret", response: "token-123", remoteip: "203.0.113.9" } ], sent
      end
    end
  end

  test "fails when Cloudflare refuses the answer" do
    with_settings(@keys) do
      with_response('{"success":false,"error-codes":["invalid-input-response"]}') do
        assert_not @adapter.passed?(@params, @request)
      end
    end
  end

  test "fails without a token and without asking Cloudflare" do
    with_settings(@keys) do
      with_response('{"success":true}') do |sent|
        assert_not @adapter.passed?({}, @request)
        assert_empty sent
      end
    end
  end

  test "fails closed on a timeout, a network error, an error status or a garbled reply" do
    with_settings(@keys) do
      [ -> { raise Net::OpenTimeout }, -> { raise Errno::ECONNREFUSED }, -> { raise SocketError }, -> { nil }, "<html>" ].each do |result|
        with_response(result) { assert_not @adapter.passed?(@params, @request) }
      end
    end
  end
end
