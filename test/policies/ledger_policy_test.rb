require "test_helper"

class LedgerPolicyTest < ActiveSupport::TestCase
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

  test "managers and admins may open the new ledger form, plain members may not" do
    assert LedgerPolicy.new(@admin_user, Ledger).new?
    assert LedgerPolicy.new(@manager_user, Ledger).new?
    assert_not LedgerPolicy.new(@member_user, Ledger).new?
  end

  test "an admin may create a ledger on any team" do
    assert LedgerPolicy.new(@admin_user, Ledger.new(team: @drama)).create?
  end

  test "a manager may create a ledger on their team and its sub-teams only" do
    assert LedgerPolicy.new(@manager_user, Ledger.new(team: @robotics)).create?
    assert LedgerPolicy.new(@manager_user, Ledger.new(team: @robotics_jr)).create?
    assert_not LedgerPolicy.new(@manager_user, Ledger.new(team: @drama)).create?
    assert_not LedgerPolicy.new(@manager_user, Ledger.new).create?
  end

  test "a plain member may not create a ledger" do
    assert_not LedgerPolicy.new(@member_user, Ledger.new(team: @robotics)).create?
  end

  test "a manager may update ledgers of their team and its sub-teams only" do
    assert LedgerPolicy.new(@manager_user, Ledger.new(team: @robotics_jr)).update?
    assert_not LedgerPolicy.new(@manager_user, Ledger.new(team: @drama)).update?
    assert_not LedgerPolicy.new(@manager_user, Ledger.new).update?
    assert_not LedgerPolicy.new(@member_user, Ledger.new(team: @robotics)).update?
  end
end
