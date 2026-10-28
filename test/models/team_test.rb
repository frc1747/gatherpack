require "test_helper"

class TeamTest < ActiveSupport::TestCase
  setup do
    @pack = Team.create!(name: "Pack", team_type: team_types(:one))
    @den = Team.create!(name: "Den", team_type: team_types(:one), parent: @pack)
    @patrol = Team.create!(name: "Patrol", team_type: team_types(:one), parent: @den)
  end

  test "a team can't be its own parent" do
    @den.parent = @den
    assert_not @den.valid?
    assert @den.errors.added?(:parent_id, :not_below_itself)
  end

  test "a team can't move under one of its descendants" do
    @pack.parent = @patrol
    assert_not @pack.valid?
    assert @pack.errors.added?(:parent_id, :not_below_itself)
  end

  test "a team can move under a team outside its subtree" do
    other = Team.create!(name: "Other", team_type: team_types(:one))
    @den.parent = other
    assert @den.valid?
    @den.parent = nil
    assert @den.valid?
  end

  test "the parent check stops on teams that already form a loop" do
    @pack.update_column(:parent_id, @patrol.id)
    team = Team.new(name: "New", team_type: team_types(:one), parent: @den)
    assert team.valid?

    @den.parent = @patrol
    assert_not @den.valid?
    assert @den.errors.added?(:parent_id, :not_below_itself)
  end
end
