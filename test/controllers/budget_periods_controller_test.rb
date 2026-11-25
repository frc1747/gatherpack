require "test_helper"

class BudgetPeriodsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

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

    @budget_period = BudgetPeriod.create!(name: "Robotics 2026", team: @robotics, starts_at: 1.month.ago, ends_at: 1.month.from_now)
  end

  # --- create -------------------------------------------------------------

  test "a manager cannot create a budget period on a team they don't manage" do
    sign_in @manager_user

    post budget_periods_path, params: { budget_period: period_params(name: "Drama 2027", team_id: @drama.id) }

    assert_not BudgetPeriod.exists?(name: "Drama 2027"), "manager of Robotics created a budget period on the Drama team"
    assert_redirected_to root_path
  end

  test "a manager can create a budget period on their team and its sub-teams" do
    sign_in @manager_user

    [ @robotics, @robotics_jr ].each do |team|
      post budget_periods_path, params: { budget_period: period_params(name: "#{team.name} 2027", team_id: team.id) }

      assert_redirected_to budget_period_path(BudgetPeriod.find_by!(name: "#{team.name} 2027", team: team))
    end
  end

  test "an admin can create a budget period on any team" do
    sign_in @admin_user

    post budget_periods_path, params: { budget_period: period_params(name: "Drama 2027", team_id: @drama.id) }

    assert_redirected_to budget_period_path(BudgetPeriod.find_by!(name: "Drama 2027", team: @drama))
  end

  # --- update -------------------------------------------------------------

  test "a manager cannot move their budget period to a team they don't manage" do
    sign_in @manager_user

    patch budget_period_path(@budget_period), params: { budget_period: { team_id: @drama.id } }

    assert_equal @robotics, @budget_period.reload.team, "manager of Robotics moved a budget period to the Drama team"
    assert_redirected_to root_path
  end

  test "a manager can rename their budget period and move it to a sub-team" do
    sign_in @manager_user

    patch budget_period_path(@budget_period), params: { budget_period: { name: "Robotics Jr 2026", team_id: @robotics_jr.id } }

    assert_redirected_to budget_period_path(@budget_period)
    assert_equal "Robotics Jr 2026", @budget_period.reload.name
    assert_equal @robotics_jr, @budget_period.team
  end

  test "an admin can move a budget period to any team" do
    sign_in @admin_user

    patch budget_period_path(@budget_period), params: { budget_period: { team_id: @drama.id } }

    assert_redirected_to budget_period_path(@budget_period)
    assert_equal @drama, @budget_period.reload.team
  end

  private

  def period_params(**attributes)
    { starts_at: 1.day.ago, ends_at: 1.year.from_now }.merge(attributes)
  end
end
