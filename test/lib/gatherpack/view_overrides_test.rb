require "test_helper"

class GatherPack::ViewOverridesTest < ActionDispatch::IntegrationTest
  FIXTURES = Rails.root.join("test/fixtures/files/view_overrides")

  setup do
    host! "localhost"
    GatherPack::ViewOverrides.reset!
  end
  teardown { GatherPack::ViewOverrides.reset! }

  test "an override replaces a template only while active" do
    on = false
    GatherPack::ViewOverrides.register(:low, path: FIXTURES.join("low"), position: 10, active: ->(_controller) { on })

    get new_user_session_path
    assert_no_match "low override sign in", response.body

    on = true
    get new_user_session_path
    assert_match "low override sign in", response.body
  end

  test "a template without an override falls through" do
    GatherPack::ViewOverrides.register(:low, path: FIXTURES.join("low"), position: 10)

    get new_user_password_path
    assert_response :success
    assert_no_match "low override", response.body
  end

  test "two overrides resolve by position, higher first" do
    GatherPack::ViewOverrides.register(:high, path: FIXTURES.join("high"), position: 20)
    GatherPack::ViewOverrides.register(:low, path: FIXTURES.join("low"), position: 10)

    get new_user_session_path
    assert_match "high override sign in", response.body
    assert_no_match "low override sign in", response.body
  end

  test "a mailer is unaffected" do
    GatherPack::ViewOverrides.register(:low, path: FIXTURES.join("low"), position: 10)

    body = DeviseGatewayMailer.render_template("reset_password_instructions", { resource: users(:one), token: "abc" })
    assert_no_match "low override mailer", body
  end

  test "the check works on a signed-out request" do
    seen = nil
    GatherPack::ViewOverrides.register(:probe, path: FIXTURES.join("low"), position: 1, active: ->(controller) { seen = controller.send(:current_user).nil? })

    get new_user_session_path
    assert seen
  end

  test "the before_action is added once" do
    ApplicationController.include(GatherPack::ViewOverrides::Controller)

    callbacks = ApplicationController._process_action_callbacks.select { |c| c.filter == :apply_view_overrides }
    assert_equal 1, callbacks.size
    assert_includes Devise::SessionsController.ancestors, GatherPack::ViewOverrides::Controller
  end
end
