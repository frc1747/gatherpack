require "test_helper"

# A database made from the schema has empty lists. Whatever first needs one
# fills it, inside or outside the inventory pages, without the seeds.
class Inventory::ListSeedingTest < ActiveSupport::TestCase
  setup do
    team_type = TeamType.first || TeamType.create!(name: "Group")
    @team = Team.create!(name: "Seeding #{SecureRandom.hex(3)}", team_type: team_type)
  end

  test "a new place, item and unit fill the lists they need" do
    assert_not LocationType.exists?
    shelf = Location.create!(team: @team, name: "Shelf")
    assert_equal "Storage", shelf.location_type.name

    assert_not StockUnit.exists?
    item = Item.create!(team: @team, name: "Motor", tracked: true, home_location: shelf)
    assert_equal "each", item.unit

    assert_not UnitCondition.exists?
    unit = ItemUnit.create!(item: item, location: shelf)
    assert_equal "New", unit.condition_label
  end

  test "the menu fills the place types" do
    assert_not LocationType.exists?
    assert_equal [ "Machines" ], LocationType.installable.map(&:plural_name)
  end
end
