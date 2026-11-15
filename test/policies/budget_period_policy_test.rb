require "test_helper"

class BudgetPeriodPolicyTest < ActiveSupport::TestCase
  setup do
    # Robotics (run by @manager)
    # └── Robotics Jr
    # Drama (unrelated)
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @robotics_jr = Team.create!(name: "Robotics Jr", team_type: team_types(:one), parent: @robotics)
    @drama = Team.create!(name: "Drama", team_type: team_types(:one))

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")

    @manager_user = User.create!(email: "manager@example.com", password: "Password1!")
    @manager = Person.create!(user: @manager_user, first_name: "Mary", last_name: "Manager")
    Membership.create!(person: @manager, team: @robotics, manager: true)

    @member_user = User.create!(email: "member@example.com", password: "Password1!")
    @member = Person.create!(user: @member_user, first_name: "Jo", last_name: "Member")
    Membership.create!(person: @member, team: @robotics)
  end

  test "managers and admins may open the new budget period form, plain members may not" do
    assert BudgetPeriodPolicy.new(@admin_user, BudgetPeriod).new?
    assert BudgetPeriodPolicy.new(@manager_user, BudgetPeriod).new?
    assert_not BudgetPeriodPolicy.new(@member_user, BudgetPeriod).new?
  end

  test "an admin may create and update budget periods on any team" do
    assert BudgetPeriodPolicy.new(@admin_user, BudgetPeriod.new(team: @drama)).create?
    assert BudgetPeriodPolicy.new(@admin_user, BudgetPeriod.new(team: @drama)).update?
  end

  test "a manager may create and update budget periods on their team and its sub-teams only" do
    [ @robotics, @robotics_jr ].each do |team|
      assert BudgetPeriodPolicy.new(@manager_user, BudgetPeriod.new(team: team)).create?
      assert BudgetPeriodPolicy.new(@manager_user, BudgetPeriod.new(team: team)).update?
    end
    assert_not BudgetPeriodPolicy.new(@manager_user, BudgetPeriod.new(team: @drama)).create?
    assert_not BudgetPeriodPolicy.new(@manager_user, BudgetPeriod.new(team: @drama)).update?
    assert_not BudgetPeriodPolicy.new(@manager_user, BudgetPeriod.new).create?
  end

  test "a plain member may not create or update a budget period" do
    assert_not BudgetPeriodPolicy.new(@member_user, BudgetPeriod.new(team: @robotics)).create?
    assert_not BudgetPeriodPolicy.new(@member_user, BudgetPeriod.new(team: @robotics)).update?
  end
end
