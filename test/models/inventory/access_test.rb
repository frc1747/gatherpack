require "test_helper"
require "support/inventory_world"

class Inventory::AccessTest < ActiveSupport::TestCase
  include InventoryWorld

  setup { @world = build_inventory_world }

  def sees?(person, record)
    Inventory::Current.reset
    Inventory::Access.for(person).sees?(record)
  end

  test "an item on a top-level team is seen from a subteam" do
    with_inventory(@world) do
      assert sees?(@world.builder, @world.screws)
      assert sees?(@world.outreacher, @world.screws)
      assert_not sees?(@world.outsider, @world.screws)
    end
  end

  test "a subteam's item isn't seen from a sibling, and is seen from the teams below" do
    with_inventory(@world) do
      kit = Item.create!(team: @world.robotics, name: "Drive kit")

      assert sees?(@world.member, kit)
      assert_not sees?(@world.outreacher, kit)
      assert sees?(@world.builder, kit), "a member of a team below sees the teams above"
      assert sees?(@world.manager, kit)
      assert sees?(@world.keeper, kit)
    end
  end

  test "a subteam's item can sit in the parent team's shop" do
    with_inventory(@world) do
      kit = Item.create!(team: @world.robotics, name: "Drive kit")

      assert record(@world, :added, 2, item: kit, reason: "Donated", person: @world.keeper)
      assert record(@world, :used, 1, item: kit, person: @world.member)
    end
  end

  test "inventory_users leaves out a team" do
    with_inventory(@world, inventory_users: "#{@world.robotics.name}\n#{@world.art.name}") do
      assert sees?(@world.member, @world.screws)
      assert sees?(@world.builder, @world.screws), "the teams below a listed team are in"
      assert_not sees?(@world.outreacher, @world.screws)
      assert_not Inventory::Access.for(@world.outreacher).user?
      assert_raises(Inventory::Refused) { record(@world, :used, 1, person: @world.outreacher) }
    end
  end

  test "managers and admins use inventory whatever inventory_users says" do
    with_inventory(@world, inventory_users: @world.art.name) do
      assert Inventory::Access.for(@world.keeper).user?
      assert Inventory::Access.for(@world.manager).user?
      assert Inventory::Access.for(@world.admin).user?
      assert_not Inventory::Access.for(@world.member).user?
    end
  end

  test "managers are inventory managers (team managers through the default row) and admins" do
    with_inventory(@world) do
      assert Inventory::Access.for(@world.keeper).manager?
      assert Inventory::Access.for(@world.manager).manager?
      assert Inventory::Access.for(@world.admin).manager?
      assert_not Inventory::Access.for(@world.member).manager?
      assert Inventory::Access.for(@world.keeper).manages?(@world.club.id)
      assert_not Inventory::Access.for(@world.manager).manages?(@world.club.id)
    end
  end
end
