require "test_helper"
require "phone_notifications_test_support"

# The replace keys page follows the screen standard: a secondary Cancel back
# to the gateway, then the red Replace keys button.
class PushKeysScreenTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PhoneNotificationsTestSupport

  setup do
    host! "localhost"
    use_throwaway_settings
    set_push_flag(true)
    @gateway = create_push_gateway
    @user = users(:one)
    @user.update_columns(architect: true)
    sign_in @user
  end

  teardown { restore_settings }

  test "the page cancels with a secondary button before Replace keys" do
    get edit_gateway_push_keys_path(@gateway)

    assert_select ".card-footer a.btn-secondary[href=?]", gateway_path(@gateway), text: "Cancel"
    assert_select ".card-footer a.btn-warning", count: 0
    assert_select ".card-footer a.btn-secondary + input.btn-danger[value=?]", "Replace keys"
  end

  test "replacing saves new keys" do
    public_key = @gateway.public_key

    patch gateway_push_keys_path(@gateway)

    assert_not_equal public_key, @gateway.reload.public_key
  end
end
