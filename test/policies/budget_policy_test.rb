require "test_helper"

class BudgetPolicyTest < ActiveSupport::TestCase
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

    @robotics_period = BudgetPeriod.new(name: "Robotics 2026", team: @robotics)
    @robotics_jr_period = BudgetPeriod.new(name: "Robotics Jr 2026", team: @robotics_jr)
    @drama_period = BudgetPeriod.new(name: "Drama 2026", team: @drama)
  end

  test "managers and admins may open the new budget form, plain members may not" do
    assert BudgetPolicy.new(@admin_user, Budget).new?
    assert BudgetPolicy.new(@manager_user, Budget).new?
    assert_not BudgetPolicy.new(@member_user, Budget).new?
  end

  test "an admin may create and update budgets in any budget period" do
    assert BudgetPolicy.new(@admin_user, Budget.new(budget_period: @drama_period)).create?
    assert BudgetPolicy.new(@admin_user, Budget.new(budget_period: @drama_period)).update?
  end

  test "a manager may create and update budgets in their teams' budget periods only" do
    [ @robotics_period, @robotics_jr_period ].each do |period|
      assert BudgetPolicy.new(@manager_user, Budget.new(budget_period: period)).create?
      assert BudgetPolicy.new(@manager_user, Budget.new(budget_period: period)).update?
    end
    assert_not BudgetPolicy.new(@manager_user, Budget.new(budget_period: @drama_period)).create?
    assert_not BudgetPolicy.new(@manager_user, Budget.new(budget_period: @drama_period)).update?
    assert_not BudgetPolicy.new(@manager_user, Budget.new).create?
  end

  test "a plain member may not create, update or delete a budget" do
    assert_not BudgetPolicy.new(@member_user, Budget.new(budget_period: @robotics_period)).create?
    assert_not BudgetPolicy.new(@member_user, Budget.new(budget_period: @robotics_period)).update?
    assert_not BudgetPolicy.new(@member_user, Budget.new(budget_period: @robotics_period)).destroy?
  end
end
