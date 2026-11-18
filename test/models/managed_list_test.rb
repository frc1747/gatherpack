require "test_helper"
require_relative "../support/managed_list_test_support"

class ManagedListTest < ActiveSupport::TestCase
  include ManagedListTestSupport

  setup do
    create_managed_list_tables
  end

  test "new rows go to the end and the list reads in order" do
    each = ManagedListTestUnit.create!(name: "Each")
    box = ManagedListTestUnit.create!(name: "Box")
    pack = ManagedListTestUnit.create!(name: "Pack")

    assert_equal [ each, box, pack ], ManagedListTestUnit.ordered.to_a
    assert_equal [ 0, 1, 2 ], [ each, box, pack ].map(&:position)
  end

  test "move! swaps a row with its neighbour and stops at the ends" do
    each = ManagedListTestUnit.create!(name: "Each")
    box = ManagedListTestUnit.create!(name: "Box")
    pack = ManagedListTestUnit.create!(name: "Pack")

    assert pack.move!(:up)
    assert_equal [ each, pack, box ], ManagedListTestUnit.ordered.to_a
    assert each.reload.move!(:down)
    assert_equal [ pack, each, box ], ManagedListTestUnit.ordered.to_a

    assert_not pack.reload.move!(:up)
    assert_not box.reload.move!(:down)
    assert_equal [ pack, each, box ], ManagedListTestUnit.ordered.to_a
  end

  test "move! skips retired rows" do
    each = ManagedListTestUnit.create!(name: "Each")
    ManagedListTestUnit.create!(name: "Box", active: false)
    pack = ManagedListTestUnit.create!(name: "Pack")

    assert pack.move!(:up)
    assert_equal [ pack, each ], ManagedListTestUnit.active.ordered.to_a
  end

  test "retire! hides a row from the active list and restore! brings it back" do
    box = ManagedListTestUnit.create!(name: "Box")

    box.retire!
    assert box.retired?
    assert_not_includes ManagedListTestUnit.active, box
    assert_includes ManagedListTestUnit.retired, box

    box.restore!
    assert_includes ManagedListTestUnit.active, box
  end

  test "names are required and unique ignoring case and spaces" do
    ManagedListTestUnit.create!(name: "Box")

    duplicate = ManagedListTestUnit.new(name: " box ")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
    assert_not ManagedListTestUnit.new(name: "").valid?
  end

  test "plural_name falls back to the pluralized name" do
    assert_equal "Boxes", ManagedListTestUnit.new(name: "Box").plural_name
    assert_equal "Feet", ManagedListTestUnit.new(name: "Foot", plural: "Feet").plural_name
  end

  test "a row in use can't be deleted" do
    box = ManagedListTestUnit.create!(name: "Box")
    ManagedListTestThing.create!(name: "Bolts", unit_id: box.id)

    assert box.in_use?
    assert_equal({ ManagedListTestThing => 1 }, box.usage)
    assert_not box.destroy
    assert_match "is in use", box.errors[:base].to_sentence
    assert ManagedListTestUnit.exists?(box.id)
  end

  test "a row that isn't used can be deleted" do
    box = ManagedListTestUnit.create!(name: "Box")

    assert_not box.in_use?
    assert box.destroy
    assert_not ManagedListTestUnit.exists?(box.id)
  end

  test "a row with a key can't be deleted or merged away" do
    each = ManagedListTestUnit.create!(name: "Each", key: "each")
    box = ManagedListTestUnit.create!(name: "Box")

    assert_not each.removable?
    assert_not each.destroy
    assert_match "built in", each.errors[:base].to_sentence
    assert_raises(ArgumentError) { each.merge_into!(box) }
  end

  test "merge_into! points every use at the other row, then deletes the row" do
    box = ManagedListTestUnit.create!(name: "Box")
    carton = ManagedListTestUnit.create!(name: "Carton")
    bolts = ManagedListTestThing.create!(name: "Bolts", unit_id: carton.id)
    nuts = ManagedListTestThing.create!(name: "Nuts", unit_id: carton.id)

    assert_difference -> { bolts.versions.count }, 1 do
      carton.merge_into!(box)
    end

    assert_equal box.id, bolts.reload.unit_id
    assert_equal box.id, nuts.reload.unit_id
    assert_not ManagedListTestUnit.exists?(carton.id)
  end

  test "merge_into! refuses the row itself" do
    box = ManagedListTestUnit.create!(name: "Box")

    assert_raises(ArgumentError) { box.merge_into!(box) }
  end

  test "changes are audited" do
    box = ManagedListTestUnit.create!(name: "Box")

    assert_difference -> { box.versions.count }, 1 do
      box.update!(name: "Boxes")
    end
  end

  test "seed_defaults! fills an empty list in order, once" do
    assert ManagedListTestUnit.seed_defaults!([ { name: "Each", key: "each" }, "Box", "Pack" ])
    assert_equal %w[Each Box Pack], ManagedListTestUnit.ordered.pluck(:name)
    assert_equal "each", ManagedListTestUnit.find_by!(name: "Each").key

    assert_not ManagedListTestUnit.seed_defaults!([ "Crate" ])
    assert_equal 3, ManagedListTestUnit.count
  end

  test "seed_defaults! leaves a list alone once it has rows" do
    ManagedListTestUnit.create!(name: "Pallet")

    assert_not ManagedListTestUnit.seed_defaults!([ "Each" ])
    assert_equal [ "Pallet" ], ManagedListTestUnit.pluck(:name)
  end
end
