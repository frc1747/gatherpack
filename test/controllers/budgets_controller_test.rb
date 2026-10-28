require "test_helper"

class BudgetsControllerTest < ActionDispatch::IntegrationTest
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

    @robotics_period = create_period(@robotics)
    @robotics_jr_period = create_period(@robotics_jr)
    @drama_period = create_period(@drama)
    @budget = Budget.create!(budget_period: @robotics_period, amount: 100)
  end

  # --- create -------------------------------------------------------------

  test "a manager cannot add a budget to another team's budget period" do
    sign_in @manager_user

    post budgets_path, params: { budget: { amount: "999", budget_period_id: @drama_period.id } }

    assert_not Budget.exists?(budget_period: @drama_period), "manager of Robotics added a budget to Drama's budget period"
    assert_redirected_to root_path
  end

  test "a manager can add a budget to their team's and its sub-teams' budget periods" do
    sign_in @manager_user

    [ @robotics_period, @robotics_jr_period ].each do |period|
      post budgets_path, params: { budget: { amount: "250", budget_period_id: period.id } }

      assert_redirected_to budget_path(Budget.where(budget_period: period).order(:created_at).last)
    end
  end

  test "an admin can add a budget to any budget period" do
    sign_in @admin_user

    post budgets_path, params: { budget: { amount: "999", budget_period_id: @drama_period.id } }

    assert_redirected_to budget_path(Budget.find_by!(budget_period: @drama_period))
  end

  # --- update -------------------------------------------------------------

  test "a manager cannot move their budget to another team's budget period" do
    sign_in @manager_user

    patch budget_path(@budget), params: { budget: { budget_period_id: @drama_period.id } }

    assert_equal @robotics_period, @budget.reload.budget_period, "manager of Robotics moved a budget into Drama's budget period"
    assert_redirected_to root_path
  end

  test "a refused budget update changes nothing, tags included" do
    tag = LedgerTag.create!(name: "Travel")
    sign_in @manager_user

    patch budget_path(@budget), params: { budget: { amount: "1", budget_period_id: @drama_period.id, ledger_tag_ids: [ tag.id ] } }

    assert_redirected_to root_path
    @budget.reload
    assert_empty @budget.ledger_tags, "a refused update tagged the budget"
    assert_equal 10_000, @budget.amount_cents
    assert_equal @robotics_period, @budget.budget_period
  end

  test "a manager can change their budget and move it to a sub-team's budget period" do
    sign_in @manager_user

    patch budget_path(@budget), params: { budget: { amount: "300", budget_period_id: @robotics_jr_period.id } }

    assert_redirected_to budget_path(@budget)
    assert_equal 30_000, @budget.reload.amount_cents
    assert_equal @robotics_jr_period, @budget.budget_period
  end

  test "an admin can move a budget to any budget period" do
    sign_in @admin_user

    patch budget_path(@budget), params: { budget: { budget_period_id: @drama_period.id } }

    assert_redirected_to budget_path(@budget)
    assert_equal @drama_period, @budget.reload.budget_period
  end

  private

  def create_period(team)
    BudgetPeriod.create!(name: "#{team.name} 2026", team: team, starts_at: 1.month.ago, ends_at: 1.month.from_now)
  end
end
