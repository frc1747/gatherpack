require "test_helper"

class LedgerTransferTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    @team = Team.create!(name: "Robotics", team_type: team_types(:one))
    @from = Ledger.create!(name: "Robotics fund", team: @team)
    @to = Ledger.create!(name: "Robotics reserve", team: @team)
  end

  test "moves the amount from one ledger to the other" do
    assert_difference -> { LedgerEntryLink.count }, 1 do
      assert build_transfer(amount: 25).create
    end
    assert_equal(-2_500, @from.reload.balance_cents)
    assert_equal 2_500, @to.reload.balance_cents
  end

  test "needs a positive amount" do
    assert_not build_transfer(amount: 0).valid?
    assert_not build_transfer(amount: -5).valid?
    assert_not build_transfer(amount: nil).valid?
  end

  test "needs two different ledgers" do
    assert_not build_transfer(to_ledger_id: @from.id).valid?
    assert_not build_transfer(to_ledger_id: @from.id.upcase).valid?
  end

  test "needs ledgers that exist" do
    assert_not build_transfer(from_ledger_id: SecureRandom.uuid).valid?
    assert_not build_transfer(to_ledger_id: "").valid?
    assert_nil build_transfer(to_ledger_id: "not-a-uuid").to_ledger
  end

  test "creates nothing when invalid" do
    assert_no_difference -> { LedgerEntry.count } do
      assert_not build_transfer(amount: 0).create
    end
  end

  private

  def build_transfer(**attributes)
    LedgerTransfer.new(from_ledger_id: @from.id, to_ledger_id: @to.id, amount: 10, **attributes).tap { |t| t.creator = @user }
  end
end
