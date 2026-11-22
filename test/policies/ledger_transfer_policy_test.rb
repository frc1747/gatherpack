require "test_helper"

class LedgerTransferPolicyTest < ActiveSupport::TestCase
  setup do
    # Pack
    # ├── Den A (run by @manager, who is also a plain member of Den B)
    # │   └── Patrol
    # └── Den B
    @pack = Team.create!(name: "Pack", team_type: team_types(:one))
    @den_a = Team.create!(name: "Den A", team_type: team_types(:one), parent: @pack)
    @patrol = Team.create!(name: "Patrol", team_type: team_types(:one), parent: @den_a)
    @den_b = Team.create!(name: "Den B", team_type: team_types(:one), parent: @pack)

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")

    @manager_user = User.create!(email: "manager@example.com", password: "Password1!")
    @manager = Person.create!(user: @manager_user, first_name: "Mary", last_name: "Manager")
    Membership.create!(person: @manager, team: @den_a, manager: true)
    Membership.create!(person: @manager, team: @den_b)

    @member_user = User.create!(email: "member@example.com", password: "Password1!")
    @member = Person.create!(user: @member_user, first_name: "Jo", last_name: "Member")
    Membership.create!(person: @member, team: @den_a)

    @pack_ledger = Ledger.create!(name: "Pack fund", team: @pack)
    @den_a_ledger = Ledger.create!(name: "Den A fund", team: @den_a)
    @den_a_reserve = Ledger.create!(name: "Den A reserve", team: @den_a)
    @patrol_ledger = Ledger.create!(name: "Patrol fund", team: @patrol)
    @den_b_ledger = Ledger.create!(name: "Den B fund", team: @den_b)
  end

  test "a manager may open the new transfer form" do
    assert LedgerTransferPolicy.new(@manager_user, LedgerTransfer.new).new?
  end

  test "a plain member may not open the new transfer form" do
    assert_not LedgerTransferPolicy.new(@member_user, LedgerTransfer.new).new?
  end

  test "an admin may transfer between any two ledgers" do
    assert create?(@admin_user, @pack_ledger, @den_b_ledger)
  end

  test "a manager may transfer between their own team's ledgers" do
    assert create?(@manager_user, @den_a_ledger, @den_a_reserve)
  end

  test "a manager may transfer from their team's ledger to another ledger they can see" do
    assert create?(@manager_user, @den_a_ledger, @den_b_ledger)
  end

  test "a manager may transfer from a sub-team's ledger" do
    assert create?(@manager_user, @patrol_ledger, @den_a_ledger)
  end

  test "a manager may not transfer out of a ledger of a team they're only a member of" do
    assert_not create?(@manager_user, @den_b_ledger, @den_a_ledger)
  end

  test "a manager may not transfer out of their parent team's ledger" do
    assert_not create?(@manager_user, @pack_ledger, @den_a_ledger)
  end

  test "a manager may not transfer into a ledger they can't see" do
    assert_not create?(@manager_user, @den_a_ledger, @pack_ledger)
  end

  test "a plain member may not transfer out of their team's ledger" do
    assert_not create?(@member_user, @den_a_ledger, @den_a_reserve)
  end

  test "a manager may not transfer to or from a ledger that doesn't exist" do
    assert_not LedgerTransferPolicy.new(@manager_user, LedgerTransfer.new(from_ledger_id: @den_a_ledger.id, to_ledger_id: SecureRandom.uuid)).create?
    assert_not LedgerTransferPolicy.new(@manager_user, LedgerTransfer.new(from_ledger_id: nil, to_ledger_id: @den_a_ledger.id)).create?
  end

  private

  def create?(user, from_ledger, to_ledger)
    LedgerTransferPolicy.new(user, LedgerTransfer.new(from_ledger_id: from_ledger.id, to_ledger_id: to_ledger.id, amount: 10)).create?
  end
end
