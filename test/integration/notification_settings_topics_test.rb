require "test_helper"
require_relative "../support/push_connector_test_support"

class NotificationSettingsTopicsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PushConnectorTestSupport

  setup do
    host! "localhost"
    apply_push_settings(signups: true)
    create_push_gateway
    @user = users(:one)
    sign_in @user
  end

  teardown { restore_push_settings }

  test "saving while a feature is off keeps the opt-in for its topic" do
    enable_topics(@user, :announcements, :shifts)
    apply_push_settings(signups: false)

    patch notifications_path, params: { topics: [ "announcements" ] }

    assert_equal %w[announcements shifts], @user.reload.push_preference.enabled_topics.sort
    apply_push_settings(signups: true)
    assert @user.reload.push_topic_enabled?(:shifts)
  end

  test "a topic that is offered can still be turned off" do
    enable_topics(@user, :announcements, :shifts)

    patch notifications_path, params: { topics: [ "announcements" ] }

    assert_equal [ "announcements" ], @user.reload.push_preference.enabled_topics
  end
end
