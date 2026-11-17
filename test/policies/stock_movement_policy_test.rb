require "test_helper"
require "support/inventory_world"

class StockMovementPolicyTest < ActiveSupport::TestCase
  include InventoryWorld

  setup { @world = build_inventory_world }

  def policy(person, record)
    Inventory::Current.reset
    StockMovementPolicy.new(person.user, record)
  end

  test "members record the member kinds; managers every kind" do
    with_inventory(@world) do
      used = StockMovement.new(kind: "used", item: @world.screws, location: @world.bin1)
      removed = StockMovement.new(kind: "removed", item: @world.screws, location: @world.bin1)

      assert policy(@world.member, used).create?
      assert_not policy(@world.member, removed).create?
      assert policy(@world.keeper, removed).create?
      assert policy(@world.admin, removed).create?
      assert_not policy(@world.outsider, used).create?
    end
  end

  test "history is seen with the item; Changes is for managers; nothing is edited or deleted" do
    with_inventory(@world) do
      movement = stock!(@world, 3)

      assert policy(@world.member, movement).show?
      assert_not policy(@world.outsider, movement).show?
      assert_not policy(@world.member, movement).index?
      assert policy(@world.keeper, movement).index?
      assert_not policy(@world.admin, movement).update?
      assert_not policy(@world.admin, movement).destroy?

      assert_includes StockMovementPolicy::Scope.new(@world.member.user, StockMovement).resolve, movement
      Inventory::Current.reset
      assert_not_includes StockMovementPolicy::Scope.new(@world.outsider.user, StockMovement).resolve, movement
    end
  end

  test "undo follows the movement's own rule" do
    with_inventory(@world) do
      stock!(@world, 3)
      used = record(@world, :used, 1, person: @world.member)

      assert policy(@world.member, used).undo?
      assert_not policy(@world.teammate, used).undo?
      assert policy(@world.keeper, used).undo?
    end
  end
end
