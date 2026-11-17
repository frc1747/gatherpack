require "test_helper"
require "support/inventory_world"

class ItemPolicyTest < ActiveSupport::TestCase
  include InventoryWorld

  setup { @world = build_inventory_world }

  def policy(klass, person, record)
    Inventory::Current.reset
    klass.new(person.user, record)
  end

  test "items are seen within the person's teams and managed within reach" do
    with_inventory(@world) do
      kit = Item.create!(team: @world.robotics, name: "Drive kit")

      assert policy(ItemPolicy, @world.member, @world.screws).show?
      assert_not policy(ItemPolicy, @world.member, @world.screws).update?
      assert policy(ItemPolicy, @world.keeper, @world.screws).update?
      assert_not policy(ItemPolicy, @world.manager, @world.screws).update?, "the screws are the club's"
      assert policy(ItemPolicy, @world.manager, kit).update?
      assert_not policy(ItemPolicy, @world.outreacher, kit).show?
      assert policy(ItemPolicy, @world.keeper, Item.new(team: @world.robotics)).create?
      assert_not policy(ItemPolicy, @world.member, Item).create?
    end
  end

  test "inactive items are seen only by those who manage them" do
    with_inventory(@world) do
      @world.screws.update!(active: false)

      assert_not policy(ItemPolicy, @world.member, @world.screws).show?
      assert policy(ItemPolicy, @world.keeper, @world.screws).show?
      assert_not_includes ItemPolicy::Scope.new(@world.member.user, Item).resolve, @world.screws
      Inventory::Current.reset
      assert_includes ItemPolicy::Scope.new(@world.keeper.user, Item).resolve, @world.screws
    end
  end

  test "the scope follows visibility" do
    with_inventory(@world) do
      kit = Item.create!(team: @world.robotics, name: "Drive kit")

      assert_equal [ @world.screws ], ItemPolicy::Scope.new(@world.outreacher.user, Item).resolve.to_a
      Inventory::Current.reset
      assert_equal [ kit, @world.screws ].map(&:id).sort, ItemPolicy::Scope.new(@world.member.user, Item).resolve.ids.sort
      Inventory::Current.reset
      assert_empty ItemPolicy::Scope.new(@world.outsider.user, Item).resolve
    end
  end

  test "places follow the same rules" do
    with_inventory(@world) do
      assert policy(LocationPolicy, @world.member, @world.bin1).show?
      assert_not policy(LocationPolicy, @world.member, @world.bin1).update?
      assert policy(LocationPolicy, @world.keeper, @world.bin1).update?
      assert policy(LocationPolicy, @world.manager, @world.robot).update?
      assert_not policy(LocationPolicy, @world.outreacher, @world.robot).show?
      assert policy(LocationPolicy, @world.keeper, Location.new(parent: @world.cabinet)).create?
      assert_not policy(LocationPolicy, @world.manager, Location.new(parent: @world.cabinet)).create?
    end
  end

  test "sources are managed with the item" do
    with_inventory(@world) do
      source = @world.screws.item_sources.create!(vendor_name: "Parts Depot")

      assert policy(ItemSourcePolicy, @world.member, source).show?
      assert_not policy(ItemSourcePolicy, @world.member, source).update?
      assert policy(ItemSourcePolicy, @world.keeper, source).update?
    end
  end

  test "the manager pages are for managers" do
    with_inventory(@world) do
      assert policy(InventoryPolicy, @world.member, :inventory).use?
      assert_not policy(InventoryPolicy, @world.member, :inventory).reorder?
      %i[keeper manager admin].each { |who| assert policy(InventoryPolicy, @world[who], :inventory).reorder?, who }
    end
    with_inventory(@world, inventory_users: @world.art.name) do
      assert_not policy(InventoryPolicy, @world.member, :inventory).use?
    end
  end

  test "unit actions follow inventory_member_unit_actions; units are edited by managers and never deleted" do
    with_inventory(@world) do
      unit = tracked_item!(@world, units: 1).item_units.first

      assert policy(ItemUnitPolicy, @world.member, unit).install?
      assert policy(ItemUnitPolicy, @world.member, unit).mark_for_repair?
      assert_not policy(ItemUnitPolicy, @world.member, unit).repaired?
      assert_not policy(ItemUnitPolicy, @world.member, unit).retire?
      assert policy(ItemUnitPolicy, @world.keeper, unit).retire?
      assert_not policy(ItemUnitPolicy, @world.member, unit).update?
      assert policy(ItemUnitPolicy, @world.keeper, unit).update?
      assert_not policy(ItemUnitPolicy, @world.admin, unit).destroy?
      assert_not policy(ItemUnitPolicy, @world.outsider, unit).show?

      event = unit.move!(to: @world.bin2, by: @world.member)
      assert policy(ItemUnitEventPolicy, @world.member, event).undo?
      assert_not policy(ItemUnitEventPolicy, @world.teammate, event).undo?
      assert_not policy(ItemUnitEventPolicy, @world.admin, event).destroy?
    end
  end
end
