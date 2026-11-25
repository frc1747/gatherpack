require "test_helper"
require "support/orders_world"

class PurchasePolicyTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "someone who sees one of its requests sees the purchase, but only their own lines" do
    with_orders(@world) do
      mine = approved_request(@world, lines: [ { description: "Mine", price: 1 } ])
      art = approved_request(@world, by: @world.outsider, team: @world.art, lines: [ { description: "Theirs", price: 1 } ])
      purchase = Orders::RecordPurchase.new(buyer: @world.admin, lines: mine.order_lines + art.order_lines,
        other_vendor_name: "Corner Store").call

      Orders::Current.reset
      requester = PurchasePolicy.new(@world.requester.user, purchase)
      assert requester.show?
      assert_not requester.full?
      assert_not requester.receipts?
      assert_equal [ "Mine" ], requester.visible_lines.map(&:description)
      assert_includes PurchasePolicy::Scope.new(@world.requester.user, Purchase).resolve, purchase

      admin = PurchasePolicy.new(@world.admin.user, purchase)
      assert admin.full?
      assert_equal 2, admin.visible_lines.size

      Orders::Current.reset
      assert_not PurchasePolicy.new(@world.builder.user, purchase).show?
      assert_not PurchasePolicy::Scope.new(@world.builder.user, Purchase).resolve.include?(purchase)
    end
  end

  test "its buyer sees all of it" do
    with_orders(@world) do
      purchase = buy(@world, approved_request(@world).order_lines.to_a)

      assert PurchasePolicy.new(@world.buyer.user, purchase).full?
      assert PurchasePolicy.new(@world.buyer.user, purchase).create?
      assert_not PurchasePolicy.new(@world.requester.user, purchase).create?
    end
  end
end
