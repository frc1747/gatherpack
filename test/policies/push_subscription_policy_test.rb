require "test_helper"
require "phone_notifications_test_support"

class PushSubscriptionPolicyTest < ActiveSupport::TestCase
  include PhoneNotificationsTestSupport

  setup do
    @owner = users(:one)
    @other = users(:two)
    @subscription = create_subscription(@owner)
  end

  test "only the owner can touch a subscription" do
    assert PushSubscriptionPolicy.new(@owner, @subscription).destroy?
    assert_not PushSubscriptionPolicy.new(@other, @subscription).destroy?
    assert_not PushSubscriptionPolicy.new(@other, @subscription).create?
  end

  test "the scope holds only a person's own rows" do
    assert_includes PushSubscriptionPolicy::Scope.new(@owner, PushSubscription).resolve, @subscription
    assert_empty PushSubscriptionPolicy::Scope.new(@other, PushSubscription).resolve
  end
end
