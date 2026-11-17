require "test_helper"
require "support/orders_world"

class VendorPolicyTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "everyone sees vendors; buyers, managers and admins manage them and see account notes" do
    with_orders(@world) do
      vendor = @world.preferred_vendor

      assert VendorPolicy.new(@world.requester.user, vendor).show?
      assert_not VendorPolicy.new(@world.requester.user, vendor).account_note?
      assert_not VendorPolicy.new(@world.requester.user, vendor).update?
      %i[buyer manager admin].each do |who|
        Orders::Current.reset
        assert VendorPolicy.new(@world[who].user, vendor).account_note?, who
        assert VendorPolicy.new(@world[who].user, vendor).update?, who
      end
    end
  end
end
