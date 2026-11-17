require "test_helper"

# Controllers load these records through the policy's Scope, so show? gives
# the same answer as the Scope for every record and user.
class ShowMatchesScopeTest < ActiveSupport::TestCase
  setup do
    @den_a = Team.create!(name: "Den A", team_type: team_types(:one))
    @den_b = Team.create!(name: "Den B", team_type: team_types(:one))
    @open_team = Team.create!(name: "Open", team_type: team_types(:one), join_permission: :has_account)

    @admin = create_person("admin", admin: true)
    @leader = create_person("leader", team: @den_a, manager: true)
    @member = create_person("member", team: @den_a)
    @owner = create_person("owner", team: @den_b)
    @loner = create_person("loner")
    @users = [ @admin, @leader, @member, @owner, @loner ].map(&:user)
  end

  test "team" do
    assert_show_matches_scope TeamPolicy, [ @den_a, @den_b, @open_team ]
    assert TeamPolicy.new(@loner.user, @open_team).show?
    assert_not TeamPolicy.new(@member.user, @den_b).show?
  end

  test "badge" do
    badges = [ @den_a, @den_b, nil ].map do |team|
      Badge.create!(name: "Badge", color: "#000000", short: "B", badge_type: badge_types(:one), team: team)
    end

    assert_show_matches_scope BadgePolicy, badges
    assert BadgePolicy.new(@member.user, badges.first).show?
    assert_not BadgePolicy.new(@member.user, badges.second).show?
  end

  test "token" do
    tokens = [ @leader, @member, @owner, @loner ].map.with_index do |person, i|
      Token.create!(value: "scope-#{i}", tokenable: person)
    end

    assert_show_matches_scope TokenPolicy, tokens
    assert TokenPolicy.new(@leader.user, tokens.second).show?
    assert_not TokenPolicy.new(@member.user, tokens.first).show?
  end

  test "announcement" do
    announcements = [ @den_a, @den_b, nil ].map do |team|
      Announcement.create!(title: "News", content: "Hello", team: team, start_time: 1.day.ago, end_time: 1.day.from_now)
    end

    assert_show_matches_scope AnnouncementPolicy, announcements
    assert AnnouncementPolicy.new(@member.user, announcements.first).show?
    assert_not AnnouncementPolicy.new(@member.user, announcements.second).show?
  end

  test "time clock period" do
    periods = [ @den_a, @den_b, nil ].map do |team|
      TimeClockPeriod.create!(name: "Build", team: team, start_time: 1.day.ago, end_time: 1.day.from_now, permission: team ? :added_by_manager : :added_by_user)
    end

    assert_show_matches_scope TimeClockPeriodPolicy, periods
    assert TimeClockPeriodPolicy.new(@member.user, periods.first).show?
    assert_not TimeClockPeriodPolicy.new(@member.user, periods.second).show?
  end

  test "ledger entry" do
    team_ledger = Ledger.create!(name: "Den A Fund", team: @den_a)
    other_ledger = Ledger.create!(name: "Den B Fund", team: @den_b)
    LedgerOwnership.create!(ledger: other_ledger, owner: @loner)
    entries = [ team_ledger, other_ledger ].map do |ledger|
      LedgerEntry.create!(ledger: ledger, amount_cents: 100, created_by: @admin)
    end

    assert_show_matches_scope LedgerEntryPolicy, entries
    assert LedgerEntryPolicy.new(@member.user, entries.first).show?
    assert_not LedgerEntryPolicy.new(@member.user, entries.second).show?
    assert LedgerEntryPolicy.new(@loner.user, entries.second).show?
  end

  private

  def assert_show_matches_scope(policy_class, records)
    @users.each do |user|
      visible = policy_class::Scope.new(user, records.first.class).resolve.where(id: records.map(&:id)).ids
      records.each do |record|
        assert_equal visible.include?(record.id), policy_class.new(user, record).show?,
          "#{policy_class.name}#show? for #{user.email} on #{record.class.name} #{record.id}"
      end
    end
  end

  def create_person(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.titleize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    person
  end
end
