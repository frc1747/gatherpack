require "test_helper"

class LedgerEntryLinkPolicyTest < ActiveSupport::TestCase
  setup do
    # Robotics (run by @manager, @member is on it)
    # Drama (unrelated)
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
    @drama_travel = Ledger.create!(name: "Drama travel", team: @drama)

    @own_link = transfer(@robotics_ledger, @robotics_reserve)
    @shared_link = transfer(@robotics_ledger, @drama_ledger)
    @other_link = transfer(@drama_ledger, @drama_travel)
    @empty_link = LedgerEntryLink.create!
    @links = [ @own_link, @shared_link, @other_link, @empty_link ]
  end

  test "an admin may see every link" do
    @links.each { |link| assert LedgerEntryLinkPolicy.new(@admin_user, link).show? }
  end

  test "others may only see links whose entries they may all see" do
    [ @manager_user, @member_user ].each do |user|
      assert LedgerEntryLinkPolicy.new(user, @own_link).show?
      assert_not LedgerEntryLinkPolicy.new(user, @shared_link).show?, "#{user.email} may see a link to another team's entry"
      assert_not LedgerEntryLinkPolicy.new(user, @other_link).show?, "#{user.email} may see a link between another team's entries"
      assert_not LedgerEntryLinkPolicy.new(user, @empty_link).show?
    end
  end

  test "a ledger owner may see a link to their own ledger's entries" do
    LedgerOwnership.create!(ledger: @drama_ledger, owner: @member)
    LedgerOwnership.create!(ledger: @drama_travel, owner: @member)

    assert LedgerEntryLinkPolicy.new(@member_user, @other_link).show?
    assert LedgerEntryLinkPolicy.new(@member_user, @shared_link).show?
  end

  test "show? agrees with the scope" do
    LedgerOwnership.create!(ledger: @drama_ledger, owner: @member)

    [ @admin_user, @manager_user, @member_user ].each do |user|
      visible = LedgerEntryLinkPolicy::Scope.new(user, LedgerEntryLink).resolve.to_a
      @links.each do |link|
        assert_equal visible.include?(link), LedgerEntryLinkPolicy.new(user, link).show?,
          "scope and show? disagree for #{user.email} on link #{@links.index(link)}"
      end
    end
  end

  test "a manager of only a parent team may change but not see a link between its sub-teams" do
    org = Team.create!(name: "Org", team_type: team_types(:one))
    @robotics.update!(parent: org)
    @drama.update!(parent: org)
    org_manager_user = User.create!(email: "org@example.com", password: "Password1!")
    Membership.create!(person: Person.create!(user: org_manager_user, first_name: "Olga", last_name: "Org"), team: org, manager: true)
    policy = LedgerEntryLinkPolicy.new(org_manager_user, @shared_link)

    assert policy.destroy?
    assert_not policy.show?
    assert_not_includes LedgerEntryLinkPolicy::Scope.new(org_manager_user, LedgerEntryLink).resolve, @shared_link
  end

  private

  def transfer(from_ledger, to_ledger)
    t = LedgerTransfer.new(from_ledger_id: from_ledger.id, to_ledger_id: to_ledger.id, amount: 10)
    t.creator = @admin_user
    t.create
    from_ledger.ledger_entries.find_by!(remark: "Transfer to #{to_ledger.name}").ledger_entry_links.first
  end
end
