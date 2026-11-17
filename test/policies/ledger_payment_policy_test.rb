require "test_helper"

class LedgerPaymentPolicyTest < ActiveSupport::TestCase
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

    @owner_user = User.create!(email: "owner@example.com", password: "Password1!")
    @owner = Person.create!(user: @owner_user, first_name: "Olly", last_name: "Owner")

    @robotics_ledger = Ledger.create!(name: "Robotics fund", team: @robotics)
    @robotics_jr_ledger = Ledger.create!(name: "Robotics Jr fund", team: @robotics_jr)
    @drama_ledger = Ledger.create!(name: "Drama fund", team: @drama)
    LedgerOwnership.create!(ledger: @drama_ledger, owner: @owner)
  end

  test "an admin may pay into any ledger" do
    assert create?(@admin_user, @drama_ledger)
  end

  test "a manager may pay into ledgers of their team and its sub-teams" do
    assert create?(@manager_user, @robotics_ledger)
    assert create?(@manager_user, @robotics_jr_ledger)
  end

  test "a manager may not pay into another team's ledger" do
    assert_not create?(@manager_user, @drama_ledger)
  end

  test "a ledger's owner may pay into it" do
    assert create?(@owner_user, @drama_ledger)
    assert_not create?(@owner_user, @robotics_ledger)
  end

  test "a plain member may not pay into their team's ledger" do
    assert_not create?(@member_user, @robotics_ledger)
  end

  private

  def create?(user, ledger)
    LedgerPaymentPolicy.new(user, LedgerPayment.new(ledger_id: ledger.id, amount: 10)).create?
  end
end
