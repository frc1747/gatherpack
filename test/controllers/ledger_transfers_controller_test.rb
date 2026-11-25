require "test_helper"

class LedgerTransfersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    # Robotics is the manager's team. They're a plain member of Boosters, and
    # have nothing to do with Drama.
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @boosters = Team.create!(name: "Boosters", team_type: team_types(:one))
    @drama = Team.create!(name: "Drama", team_type: team_types(:one))

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")

    @manager_user = User.create!(email: "manager@example.com", password: "Password1!")
    @manager = Person.create!(user: @manager_user, first_name: "Mary", last_name: "Manager")
    Membership.create!(person: @manager, team: @robotics, manager: true)
    Membership.create!(person: @manager, team: @boosters)

    @robotics_ledger = Ledger.create!(name: "Robotics fund", team: @robotics)
    @boosters_ledger = Ledger.create!(name: "Boosters fund", team: @boosters)
    @drama_ledger = Ledger.create!(name: "Drama fund", team: @drama)
    @drama_reserve = Ledger.create!(name: "Drama reserve", team: @drama)
    [ @robotics_ledger, @drama_ledger ].each do |ledger|
      LedgerEntry.create!(ledger: ledger, amount_cents: 50_000, remark: "Seed", created_by: @admin_user)
    end
  end

  test "a manager can't move money out of another team's ledger" do
    sign_in @manager_user

    post ledger_transfers_path, params: { ledger_transfer: { from_ledger_id: @drama_ledger.id, to_ledger_id: @robotics_ledger.id, amount: "500.00" } }

    assert_equal 50_000, @drama_ledger.reload.balance_cents
    assert_equal 50_000, @robotics_ledger.reload.balance_cents
    assert_redirected_to root_path
  end

  test "a manager can't move money between two ledgers of a team they don't manage" do
    sign_in @manager_user

    post ledger_transfers_path, params: { ledger_transfer: { from_ledger_id: @drama_ledger.id, to_ledger_id: @drama_reserve.id, amount: "100.00" } }

    assert_equal 0, @drama_reserve.reload.balance_cents
    assert_redirected_to root_path
  end

  test "a manager can't send money to a ledger they can't see" do
    sign_in @manager_user

    post ledger_transfers_path, params: { ledger_transfer: { from_ledger_id: @robotics_ledger.id, to_ledger_id: @drama_ledger.id, amount: "100.00" } }

    assert_equal 50_000, @robotics_ledger.reload.balance_cents
    assert_redirected_to root_path
  end

  test "a manager can transfer from their team's ledger to another ledger they can see" do
    sign_in @manager_user

    post ledger_transfers_path, params: { ledger_transfer: { from_ledger_id: @robotics_ledger.id, to_ledger_id: @boosters_ledger.id, amount: "100.00" } }

    assert_redirected_to ledger_path(@boosters_ledger)
    assert_equal 40_000, @robotics_ledger.reload.balance_cents
    assert_equal 10_000, @boosters_ledger.reload.balance_cents
  end

  test "an admin can transfer between any two ledgers" do
    sign_in @admin_user

    post ledger_transfers_path, params: { ledger_transfer: { from_ledger_id: @drama_ledger.id, to_ledger_id: @drama_reserve.id, amount: "100.00" } }

    assert_redirected_to ledger_path(@drama_reserve)
    assert_equal 40_000, @drama_ledger.reload.balance_cents
    assert_equal 10_000, @drama_reserve.reload.balance_cents
  end

  test "a manager naming a ledger that doesn't exist is refused" do
    sign_in @manager_user

    post ledger_transfers_path, params: { ledger_transfer: { from_ledger_id: @robotics_ledger.id, to_ledger_id: SecureRandom.uuid, amount: "100.00" } }

    assert_redirected_to root_path
    assert_equal 50_000, @robotics_ledger.reload.balance_cents
  end

  test "an admin naming a ledger that doesn't exist gets the form back" do
    sign_in @admin_user

    assert_no_difference -> { LedgerEntry.count } do
      post ledger_transfers_path, params: { ledger_transfer: { from_ledger_id: "", to_ledger_id: @drama_ledger.id, amount: "100.00" } }
    end

    assert_response :unprocessable_entity
  end
end
