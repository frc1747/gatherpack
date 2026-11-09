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

    @member_user = User.create!(email: "member@example.com", password: "Password1!")
    @member = Person.create!(user: @member_user, first_name: "Jo", last_name: "Member")
    Membership.create!(person: @member, team: @robotics)

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

  test "a plain member can't change their team's budget" do
    tag = LedgerTag.create!(name: "Stipends")
    sign_in @member_user

    patch budget_path(@budget), params: { budget: { amount: "1", ledger_tag_ids: [ tag.id ] } }

    assert_equal 10_000, @budget.reload.amount_cents, "a plain member changed their team's budget"
    assert_empty @budget.ledger_tags
    assert_redirected_to root_path
  end

  # --- destroy ------------------------------------------------------------

  test "a plain member can't delete their team's budget" do
    sign_in @member_user

    delete budget_path(@budget)

    assert Budget.exists?(@budget.id), "a plain member deleted their team's budget"
    assert_redirected_to root_path
  end

  # --- show ---------------------------------------------------------------

  test "a budget page doesn't list or count another team's entries with the same tags" do
    tag = tag_budget
    entry(Ledger.create!(name: "Drama fund", team: @drama), -42, "Stipend for a Drama mentor", tag)
    entry(Ledger.create!(name: "Robotics fund", team: @robotics), -10, "Robotics travel", tag)

    [ @admin_user, @manager_user, @member_user ].each do |user|
      sign_in user
      get budget_path(@budget)

      assert_response :success
      assert_not response.body.include?("Stipend for a Drama mentor"), "#{user.email} saw another team's entry on a budget page"
      assert response.body.include?("Robotics travel"), "#{user.email} didn't see their team's entry on a budget page"
      assert_equal "+$90.00", remaining_amount, "the remaining amount counted another team's entry"
    end
  end

  test "a budget page doesn't list or count a sub-team's entries with the same tags" do
    tag = tag_budget
    entry(Ledger.create!(name: "Robotics fund", team: @robotics), -10, "Robotics travel", tag)
    entry(Ledger.create!(name: "Robotics Jr fund", team: @robotics_jr), -5, "Robotics Jr travel", tag)

    [ @admin_user, @manager_user, @member_user ].each do |user|
      sign_in user
      get budget_path(@budget)

      assert_response :success
      assert response.body.include?("Robotics travel"), "#{user.email} didn't see their team's entry on a budget page"
      assert_not response.body.include?("Robotics Jr travel"), "#{user.email} saw a sub-team's entry on a budget page"
      assert_equal "+$90.00", remaining_amount, "the remaining amount counted a sub-team's entry"
    end
  end

  test "a member of another team can't open a budget" do
    sign_in @member_user

    get budget_path(Budget.create!(budget_period: @drama_period, amount: 100))

    assert_response :not_found
  end

  private

  def remaining_amount
    css_select(".card-body .col.fs-4 .money").first&.text
  end

  def tag_budget
    tag = LedgerTag.create!(name: "Travel")
    @budget.update!(ledger_tags: [ tag ])
    tag
  end

  def entry(ledger, amount, remark, *tags)
    LedgerEntry.create!(ledger: ledger, amount: amount, remark: remark, created_by: @admin_user, ledger_tags: tags)
  end

  def create_period(team)
    BudgetPeriod.create!(name: "#{team.name} 2026", team: team, starts_at: 1.month.ago, ends_at: 1.month.from_now)
  end
end
