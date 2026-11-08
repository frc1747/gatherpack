require "test_helper"
require "open3"
require "json"
require "phone_notifications_test_support"

class PhoneNotificationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers
  include PhoneNotificationsTestSupport

  KEYS = { p256dh: "BPublicKey", auth: "authSecret" }.freeze
  JSON_REQUEST = { "Accept" => "application/json" }.freeze

  setup do
    host! "localhost"
    use_throwaway_settings
    set_push_flag(true)
    @gateway = create_push_gateway
    @user = users(:one)
    @other = users(:two)
    sign_in @user
  end

  teardown { restore_settings }

  def subscribe(endpoint: ENDPOINT, **overrides)
    post push_subscription_path, params: { endpoint: endpoint, **KEYS, **overrides }, headers: JSON_REQUEST
  end

  def sync(endpoint: ENDPOINT)
    post sync_push_subscription_path, params: { endpoint: endpoint }, headers: JSON_REQUEST
  end

  def impersonate_other
    @user.update_columns(admin: true)
    post impersonate_person_path(@other.person)
  end

  test "the flag defaults to off" do
    assert_equal false, GatherPack::Features.all.find { |f| f.key == :phone_notifications }.default_enabled
  end

  # Subscribing

  test "the toggle attaches this device" do
    subscribe

    assert_response :created
    row = PushSubscription.find_by!(endpoint: ENDPOINT)
    assert_equal @user, row.user
    assert_equal "authSecret", row.auth
  end

  test "an endpoint outside the push services is refused" do
    subscribe(endpoint: "https://internal.example.test/x")

    assert_response :unprocessable_entity
    assert_equal 0, PushSubscription.count
  end

  test "opting in on a device held by someone else moves it to the person who opted in" do
    row = create_subscription(@other)

    subscribe

    assert_response :created
    assert_equal @user, row.reload.user
    assert_equal 1, PushSubscription.count
  end

  test "signed-out people can't subscribe" do
    sign_out @user
    subscribe

    assert_equal 0, PushSubscription.count
  end

  test "impersonating can't subscribe" do
    impersonate_other
    subscribe

    assert_response :forbidden
    assert_equal 0, PushSubscription.count
  end

  test "impersonating can't open the settings page" do
    impersonate_other
    get notifications_path

    assert_redirected_to root_path
  end

  test "impersonating can't sync, so an admin's own device isn't dropped" do
    row = create_subscription(@user)
    impersonate_other

    sync

    assert_response :forbidden
    assert_equal @user, row.reload.user
  end

  test "impersonating can't change topics" do
    impersonate_other
    patch notifications_path, params: { topics: [ "announcements" ] }

    assert_nil @other.reload.push_preference
  end

  test "impersonating sees no sidebar entry" do
    get root_path
    assert_select "[data-controller='push-sync']"

    impersonate_other
    get root_path
    assert_select "[data-controller='push-sync']", false
  end

  # Sync

  test "sync never creates a row" do
    sync

    assert_response :success
    assert_equal false, response.parsed_body["known"]
    assert_equal 0, PushSubscription.count
  end

  test "sync never moves a row to a different user" do
    row = create_subscription(@other)

    sync

    assert_equal false, response.parsed_body["known"]
    assert_equal @other, row.reload.user
  end

  test "sync updates a row that already belongs to this person" do
    row = create_subscription(@user)

    post sync_push_subscription_path, params: { endpoint: ENDPOINT }, headers: JSON_REQUEST.merge("User-Agent" => "Mozilla/5.0 (Linux; Android 14) Chrome/130 Safari/537")

    assert_equal true, response.parsed_body["known"]
    assert_equal "Chrome on Android", row.reload.device_label
  end

  # Sign-out

  test "signing out deletes this device's subscription and no other" do
    subscribe
    tablet = create_subscription(@user, endpoint: "#{ENDPOINT}-tablet")

    delete destroy_user_session_path

    assert_not PushSubscription.exists?(endpoint: ENDPOINT)
    assert PushSubscription.exists?(tablet.id)
  end

  test "sign-out finds a device that was attached before this session, through sync" do
    create_subscription(@user)
    sync

    delete destroy_user_session_path

    assert_equal 0, PushSubscription.count
  end

  # Removing devices

  test "another device of mine can be removed" do
    row = create_subscription(@user)

    delete push_subscription_path(id: row)

    assert_redirected_to notifications_path
    assert_not PushSubscription.exists?(row.id)
  end

  test "another user's row can't be touched" do
    row = create_subscription(@other)

    delete push_subscription_path(id: row)
    assert_response :not_found

    sign_in @user
    delete push_subscription_path, params: { endpoint: ENDPOINT }, headers: JSON_REQUEST
    assert_response :no_content

    assert PushSubscription.exists?(row.id)
  end

  test "turning off this device removes it" do
    subscribe

    delete push_subscription_path, params: { endpoint: ENDPOINT }, headers: JSON_REQUEST

    assert_response :no_content
    assert_equal 0, PushSubscription.count
  end

  # Settings page

  test "the settings page lists topics and doesn't list this device as another one" do
    subscribe
    create_subscription(@user, endpoint: "#{ENDPOINT}-tablet").update!(device_label: "Chrome on Android")

    get notifications_path

    assert_response :success
    assert_select "label", text: "Notify me on this phone"
    assert_select "label", text: "Announcements"
    assert_select "#topic_announcements:not([checked])"
    assert_select "li.list-group-item", count: 1
    assert_select "li.list-group-item", /Chrome on Android/
  end

  test "topics save for the person, ignoring unknown ones" do
    patch notifications_path, params: { topics: [ "announcements", "nonsense" ] }

    assert_redirected_to notifications_path
    assert_equal [ "announcements" ], @user.reload.push_preference.enabled_topics

    patch notifications_path

    assert_equal [], @user.reload.push_preference.enabled_topics
  end

  test "the settings page says when nothing is set up" do
    @gateway.destroy!

    get notifications_path

    assert_response :success
    assert_select "input#push_this_device", false
    assert_match "aren't set up yet", response.body
  end

  test "nothing is reachable with the flag off, and the sidebar has no entry" do
    set_push_flag(false)

    get notifications_path
    assert_redirected_to root_path

    subscribe
    assert_response :forbidden

    get root_path
    assert_select "[data-controller='push-sync']", false
  end

  test "subscriptions stay while the flag is off, so a brief off doesn't lose opt-ins" do
    row = create_subscription(@user)
    set_push_flag(false)
    get root_path

    assert PushSubscription.exists?(row.id)
  end

  test "keys and endpoints stay out of the logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    filtered = filter.filter("endpoint" => ENDPOINT, "p256dh" => "x", "auth" => "y", "author" => "kept")

    assert_equal "[FILTERED]", filtered["endpoint"]
    assert_equal "[FILTERED]", filtered["p256dh"]
    assert_equal "[FILTERED]", filtered["auth"]
    assert_equal "kept", filtered["author"]
  end

  test "the permission prompt is only reachable from the toggle" do
    controllers = Rails.root.glob("app/javascript/controllers/push_*_controller.js").map(&:read)

    assert_equal 3, controllers.size
    assert_empty controllers.flat_map { |source| source.lines.grep(/requestPermission/) }.reject { |line| line.include?("await Notification.requestPermission()") }
    assert_equal 1, controllers.join.scan("requestPermission").size
    assert_match(/async turnOn\(registration\) \{\n\s+const permission = await Notification\.requestPermission\(\)/, controllers.join)
    assert_no_match(/requestPermission/, Rails.root.join("app/javascript/controllers/push_sync_controller.js").read)
  end

  # Setting up the gateway

  test "an architect sets up the gateway from the gateways pages" do
    @gateway.destroy!
    @user.update_columns(architect: true)

    get new_gateway_path(type: "Gateway::WebPushGateway")
    assert_response :success

    perform_enqueued_jobs(only: FinalizeGatewaySetupJob) do
      post gateways_path, params: { type: "Gateway::WebPushGateway", gateway: { name: "Phones", contact: "admin@example.com" } }
    end

    gateway = Gateway::WebPushGateway.first
    assert gateway.ready?
    assert_equal gateway, GatherPack::PushChannel.gateway

    get gateway_path(gateway)
    assert_response :success
    assert_select "a[href='#{edit_gateway_push_keys_path(gateway)}']", text: "Replace keys"
  end

  test "the gateway form says why a second gateway wasn't created" do
    @user.update_columns(architect: true)

    post gateways_path, params: { type: "Gateway::WebPushGateway", gateway: { name: "Spare", contact: "admin@example.com" } }

    assert_response :unprocessable_entity
    assert_match "already has a gateway", response.body
    assert_equal 1, Gateway::WebPushGateway.count
  end

  # Replacing keys

  test "the replace keys page warns above its save button, for architects only" do
    get edit_gateway_push_keys_path(@gateway)
    assert_redirected_to root_path

    @user.update_columns(architect: true)
    get edit_gateway_push_keys_path(@gateway)

    assert_response :success
    assert_match "turns off notifications on every device", response.body
    assert_operator response.body.index("turns off notifications"), :<, response.body.index('value="Replace keys"')
  end

  test "replacing keys needs an architect" do
    public_key = @gateway.public_key

    patch gateway_push_keys_path(@gateway)
    assert_equal public_key, @gateway.reload.public_key

    @user.update_columns(architect: true)
    patch gateway_push_keys_path(@gateway)
    assert_not_equal public_key, @gateway.reload.public_key
  end

  test "replacing keys is closed while the flag is off, so opt-ins survive a brief off" do
    @user.update_columns(architect: true)
    public_key = @gateway.public_key
    row = create_subscription(@user)
    set_push_flag(false)

    get edit_gateway_push_keys_path(@gateway)
    assert_redirected_to root_path

    patch gateway_push_keys_path(@gateway)
    assert_redirected_to root_path
    assert_equal public_key, @gateway.reload.public_key
    assert PushSubscription.exists?(row.id)

    get gateway_path(@gateway)
    assert_response :success
    assert_select "a", text: "Replace keys", count: 0
  end

  # Service worker

  def service_worker_run(click_windows: [])
    get "/service-worker", headers: { "Accept" => "*/*" }
    assert_response :success
    harness = file_fixture("service_worker_push_harness.js").to_s
    output, status = Open3.capture2("node", harness, click_windows.to_json, stdin_data: response.body)
    assert status.success?, output
    JSON.parse(output)
  end

  test "the worker shows the title and carries only the path" do
    result = service_worker_run

    assert_equal "Practice moved", result["shown"]["title"]
    assert_equal({ "data" => { "path" => "/announcements/1" } }, result["shown"]["options"])
  end

  test "a tap opens the path in a new window when none is open" do
    result = service_worker_run

    assert_equal "https://example.test/announcements/1", result["opened"]
    assert result["closed"]
  end

  test "a tap focuses an existing window" do
    result = service_worker_run(click_windows: [ "https://example.test/people" ])

    assert_nil result["opened"]
    assert_equal "https://example.test/announcements/1", result["navigated"]
  end

  test "a tap never leaves the site" do
    result = service_worker_run

    assert_equal "https://example.test/", result["foreign_opened"]
  end

  test "the worker has no push handlers with the flag off" do
    set_push_flag(false)
    get "/service-worker", headers: { "Accept" => "*/*" }

    assert_no_match(/addEventListener\("push"/, response.body)
    assert_no_match(/notificationclick/, response.body)
  end
end
