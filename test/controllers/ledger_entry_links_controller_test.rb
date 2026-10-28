require "test_helper"

class LedgerEntryLinksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

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

  test "a plain member can't unlink a transfer" do
    link = transfer(@drama_ledger, @robotics_ledger)
    sign_in @member_user

    delete ledger_entry_link_path(link)

    assert LedgerEntryLink.exists?(link.id), "a plain member unlinked a transfer"
    assert_redirected_to root_path
  end

  test "a manager of one side can't unlink a transfer" do
    link = transfer(@drama_ledger, @robotics_ledger)
    sign_in @manager_user

    delete ledger_entry_link_path(link)

    assert LedgerEntryLink.exists?(link.id), "manager of Robotics unlinked a transfer with Drama"
    assert_redirected_to root_path
  end

  test "a manager of both sides can unlink a transfer" do
    link = transfer(@robotics_ledger, @robotics_reserve)
    sign_in @manager_user

    delete ledger_entry_link_path(link)

    assert_not LedgerEntryLink.exists?(link.id)
    assert_redirected_to ledger_entry_links_path
  end

  test "an admin can unlink any transfer" do
    link = transfer(@drama_ledger, @robotics_ledger)
    sign_in @admin_user

    delete ledger_entry_link_path(link)

    assert_not LedgerEntryLink.exists?(link.id)
    assert_redirected_to ledger_entry_links_path
  end

  test "a plain member can't create an empty link" do
    sign_in @member_user

    assert_no_difference -> { LedgerEntryLink.count } do
      post ledger_entry_links_path
    end
    assert_redirected_to root_path
  end

  private

  def transfer(from_ledger, to_ledger)
    t = LedgerTransfer.new(from_ledger_id: from_ledger.id, to_ledger_id: to_ledger.id, amount: 10)
    t.creator = @admin_user
    t.create
    from_ledger.ledger_entries.find_by!(remark: "Transfer to #{to_ledger.name}").ledger_entry_links.first
  end
end
