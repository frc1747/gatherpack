require "test_helper"

class LedgerEntryPolicyTest < ActiveSupport::TestCase
  setup do
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @drama = Team.create!(name: "Drama", team_type: team_types(:one))

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")

    @manager_user = User.create!(email: "manager@example.com", password: "Password1!")
    @manager = Person.create!(user: @manager_user, first_name: "Mary", last_name: "Manager")
    Membership.create!(person: @manager, team: @robotics, manager: true)

    @member_user = User.create!(email: "member@example.com", password: "Password1!")
    @member = Person.create!(user: @member_user, first_name: "Jo", last_name: "Member")
    Membership.create!(person: @member, team: @robotics)

    @robotics_ledger = Ledger.create!(name: "Robotics fund", team: @robotics)
    @robotics_reserve = Ledger.create!(name: "Robotics reserve", team: @robotics)
    @drama_ledger = Ledger.create!(name: "Drama fund", team: @drama)
  end

  test "a manager may change an ordinary entry in their team's ledger, a plain member may not" do
    entry = LedgerEntry.create!(ledger: @robotics_ledger, amount_cents: 500, remark: "Bake sale", created_by: @admin_user)

    assert allowed?(@manager_user, entry)
    assert_not allowed?(@member_user, entry)
  end

  test "a manager may not change their half of a transfer with another team" do
    _, incoming = transfer(@drama_ledger, @robotics_ledger)

    assert_not allowed?(@manager_user, incoming)
  end

  test "a manager may change a transfer between two of their team's ledgers" do
    outgoing, incoming = transfer(@robotics_ledger, @robotics_reserve)

    assert allowed?(@manager_user, outgoing)
    assert allowed?(@manager_user, incoming)
  end

  test "an admin may change either half of any transfer" do
    outgoing, incoming = transfer(@drama_ledger, @robotics_ledger)

    assert allowed?(@admin_user, outgoing)
    assert allowed?(@admin_user, incoming)
  end

  private

  def allowed?(user, entry)
    policy = LedgerEntryPolicy.new(user, entry)
    results = [ policy.edit?, policy.update?, policy.destroy? ]
    assert_equal 1, results.uniq.size, "edit?, update? and destroy? disagree"
    results.first
  end

  def transfer(from_ledger, to_ledger)
    t = LedgerTransfer.new(from_ledger_id: from_ledger.id, to_ledger_id: to_ledger.id, amount: 10)
    t.creator = @admin_user
    t.create
    [ from_ledger.ledger_entries.find_by!(remark: "Transfer to #{to_ledger.name}"),
      to_ledger.ledger_entries.find_by!(remark: "Transfer from #{from_ledger.name}") ]
  end
end
