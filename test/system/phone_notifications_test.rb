require "application_system_test_case"
require "phone_notifications_test_support"

class PhoneNotificationsSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers
  include PhoneNotificationsTestSupport

  # A browser with no push service: records every permission prompt and hands
  # back a subscription, so the page's own code runs for real.
  FAKE_PUSH = <<~JS.freeze
    (() => {
      const state = window.__push = { prompts: 0, subscribed: localStorage.getItem("fakePush") === "on", unsubscribed: 0 }
      const subscription = {
        endpoint: "#{ENDPOINT}",
        toJSON: () => ({ endpoint: "#{ENDPOINT}", keys: { p256dh: "BPublicKey", auth: "authSecret" } }),
        unsubscribe: async () => { state.subscribed = false; state.unsubscribed += 1; localStorage.removeItem("fakePush"); return true }
      }
      const registration = { pushManager: {
        getSubscription: async () => state.subscribed ? subscription : null,
        subscribe: async () => { state.subscribed = true; localStorage.setItem("fakePush", "on"); return subscription }
      } }
      Object.defineProperty(navigator.serviceWorker, "ready", { get: () => Promise.resolve(registration), configurable: true })
      navigator.serviceWorker.getRegistration = async () => registration
      Notification.requestPermission = async () => { state.prompts += 1; return window.__permission || "granted" }
      Object.defineProperty(Notification, "permission", { get: () => "default", configurable: true })
    })()
  JS

  setup do
    use_throwaway_settings
    set_push_flag(true)
    create_push_gateway
    @user = users(:one)
    sign_in @user
    @fake_push = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: FAKE_PUSH)["identifier"]
  end

  # The browser is reused between tests, so the fake must go.
  teardown do
    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: @fake_push)
    restore_settings
  end

  def visit_local(path)
    visit "http://localhost:#{Capybara.current_session.server.port}#{path}"
  end

  def prompts
    page.evaluate_script("window.__push.prompts")
  end

  def wait_until
    deadline = Time.now + 5
    sleep 0.1 until yield || Time.now > deadline
    assert yield
  end

  test "the permission prompt appears only from the toggle" do
    visit_local notifications_path
    assert_field "Notify me on this phone", disabled: false, checked: false
    assert_equal 0, prompts

    check "Notify me on this phone"

    wait_until { PushSubscription.exists?(endpoint: ENDPOINT, user: @user) }
    assert_equal 1, prompts
  end

  test "turning the toggle off removes the device" do
    create_subscription(@user)
    visit_local root_path
    page.execute_script('localStorage.setItem("fakePush", "on")')

    visit_local notifications_path
    assert_field "Notify me on this phone", disabled: false, checked: true

    uncheck "Notify me on this phone"

    wait_until { !PushSubscription.exists?(endpoint: ENDPOINT) }
    assert_equal 0, prompts
  end

  test "a browser holding someone else's subscription drops it on load and never prompts" do
    create_subscription(users(:two))
    visit_local root_path
    page.execute_script('localStorage.setItem("fakePush", "on")')

    visit_local root_path

    wait_until { page.evaluate_script("window.__push.unsubscribed") == 1 }
    assert_equal users(:two), PushSubscription.find_by!(endpoint: ENDPOINT).user
    assert_equal 0, prompts
  end

  test "choosing a topic saves it" do
    visit_local notifications_path
    assert_no_selector "#topic_announcements:checked"

    check "Announcements"

    wait_until { @user.reload.push_preference&.enabled_topics == [ "announcements" ] }
  end
end
