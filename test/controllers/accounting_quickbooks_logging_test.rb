require "test_helper"
require_relative "../support/accounting_world"

# What the request log may show of QuickBooks' sign-in redirect and change
# notifications: filtered_parameters is what Rails writes as "Parameters".
class AccountingQuickbooksLoggingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include AccountingWorld

  setup do
    host! "localhost"
    @gateway = create_quickbooks_gateway
    @architect = create_accounting_user("Architect", admin: true, architect: true)
    @fake = fake_quickbooks
  end

  teardown { reset_fake_quickbooks }

  test "the callback's code, state and realm id are filtered" do
    sign_in @architect
    @fake.on(:post, Accounting::Quickbooks::TOKEN_URL, body: qbo_fixture("token"))
    @fake.on(:get, "/companyinfo/", body: qbo_fixture("company_info"))
    log = capture_request_log do
      with_accounting do
        get connect_accounting_connection_path(@gateway)
        state = Rack::Utils.parse_query(URI(response.location).query)["state"]
        get accounting_quickbooks_callback_path(code: "secret-auth-code", state: state, realmId: AccountingWorld::REALM)
      end
    end

    assert_redirected_to gateway_path(@gateway)
    filtered = request.filtered_parameters
    assert_equal [ "[FILTERED]" ] * 3, filtered.values_at("code", "state", "realmId")
    assert_no_match(/secret-auth-code|#{AccountingWorld::REALM}/, log)
    assert_match "Parameters", log
  end

  test "a code on any other route is filtered too, in the parameters and the logged path" do
    sign_in @architect
    log = capture_request_log { get accounting_rules_path(code: "other-code", state: "other-state") }

    assert_equal [ "[FILTERED]" ] * 2, request.filtered_parameters.values_at("code", "state")
    assert_no_match(/other-code|other-state/, request.filtered_path)
    assert_equal "/accounting/rules?code=[FILTERED]&state=[FILTERED]", request.filtered_path
    assert_no_match(/other-code|other-state/, log)
  end

  test "a notification's account and entity ids are filtered" do
    body = qbo_fixture("webhook")
    log = capture_request_log do
      with_accounting do
        post webhook_gateway_path(@gateway), params: body, headers: { "Content-Type" => "application/json", "intuit-signature" => sign_webhook(body) }
      end
    end

    assert_response :no_content
    events = request.filtered_parameters["_json"]
    assert_equal 5, events.size
    events.each { |event| assert_equal [ "[FILTERED]" ] * 2, event.values_at("intuitaccountid", "intuitentityid") }
    assert_no_match(/#{AccountingWorld::REALM}|4620816365000000/, log)
    assert_no_match(/"intuitentityid"=>"(130|143)"/, log)
  end

  private
    def capture_request_log
      io = StringIO.new
      previous = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(io)
      ActionController::Base.logger = Rails.logger
      yield
      io.string
    ensure
      Rails.logger = previous
      ActionController::Base.logger = previous
    end
end
