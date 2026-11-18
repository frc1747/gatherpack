require "test_helper"
require "phone_notifications_test_support"

class PhoneNotificationsAccountLinkTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PhoneNotificationsTestSupport

  setup do
    host! "localhost"
    use_throwaway_settings
    set_push_flag(true)
    create_push_gateway
    sign_in users(:one)
  end

  teardown { restore_settings }

  test "with My GatherPack on, Notifications sits beside Sign Out and leaves the menu" do
    Settings[:feature_my_gatherpack] = "true"

    get root_path

    assert_select ".mg-sidebar-account a[href=?]", notifications_path, text: "Notifications"
    assert_select ".mg-sidebar-foot > div a[href=?]:not(.mg-sign-out)", notifications_path, count: 0
    assert_select "[data-controller='push-sync']", 1
  end

  test "with My GatherPack off, Notifications stays in the menu" do
    Settings[:feature_my_gatherpack] = "false"

    get root_path

    assert_select ".mg-sidebar-account", false
    assert_select "[data-controller='push-sync'] a[href=?]", notifications_path, text: /Notifications/
  end

  test "impersonating sees no link" do
    Settings[:feature_my_gatherpack] = "true"
    users(:one).update_columns(admin: true)
    post impersonate_person_path(users(:two).person)

    get root_path

    assert_select ".mg-sidebar-account a[href=?]", notifications_path, count: 0
  end
end
