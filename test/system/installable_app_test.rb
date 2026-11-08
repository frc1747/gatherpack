require "application_system_test_case"

class InstallableAppSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  # The flag is set through Settings against a throwaway store, so the shared
  # settings file is never written and this works whether or not a build caches
  # values on the Setting objects.
  setup do
    sign_in users(:one)
    @settings_store = Settings.instance.store
    @settings_file = Tempfile.new([ "settings", ".pstore" ])
    Settings.instance.store = PStore.new(@settings_file.path)
    @original = Settings.get(:feature_installable_app).instance_variable_get(:@value)
  end

  teardown do
    Settings.get(:feature_installable_app).instance_variable_set(:@value, @original)
    Settings.instance.store = @settings_store
    @settings_file.close!
  end

  def set_flag(on)
    Settings.set(:feature_installable_app, on.to_s)
  end

  # The test server listens on 127.0.0.1, which the app's host list doesn't
  # allow; "localhost" reaches the same server and is a secure origin.
  def visit_home
    visit "http://localhost:#{Capybara.current_session.server.port}#{root_path}"
  end

  def registered?
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      navigator.serviceWorker.getRegistration().then((registration) => done(!!registration))
    JS
  end

  def wait_for_registration(expected)
    deadline = Time.now + 10
    sleep 0.2 until registered? == expected || Time.now > deadline
    assert_equal expected, registered?
  end

  test "the worker installs with the flag on and removes itself when it is turned off" do
    set_flag(true)
    visit_home
    wait_for_registration(true)

    set_flag(false)
    page.driver.browser.execute_script("navigator.serviceWorker.getRegistration().then((r) => r.update())")
    wait_for_registration(false)
  end

  test "the install entry stays hidden on a desktop browser" do
    set_flag(true)
    visit_home

    assert_no_text "Add to Home Screen"
  end
end
