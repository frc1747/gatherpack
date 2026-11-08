require "test_helper"

class BadgeAssignmentPolicyTest < ActiveSupport::TestCase
  # Kinds members may take for themselves, and whether that needs them on the
  # badge's team.
  SELF_KINDS = { "added_by_admin_or_self" => false, "added_by_manager_or_self" => false, "has_account" => false, "added_by_current_member" => true }

  setup do
    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @other_team = Team.create!(name: "Den B", team_type: team_types(:one))
    @admin = create_person("admin", admin: true)
    @manager = create_person("manager", team: @team, manager: true)
    @member = create_person("member", team: @team)
    @teammate = create_person("teammate", team: @team)
    @outsider = create_person("outsider", team: @other_team)
  end

  test "members give the self kinds only to themselves" do
    Badge.permissions.each_key do |permission|
      badge = build_badge(permission, team: @team)
      self_kind = SELF_KINDS.key?(permission)
      assert_equal self_kind, policy(@member, badge, @member).create?, permission
      assert_equal self_kind, policy(@member, badge, @member).destroy?, permission
      assert_equal self_kind, policy(@member, badge, nil).new?, permission
      assert_not policy(@member, badge, @teammate).create?, permission
      assert_not policy(@member, badge, @teammate).destroy?, permission
    end
  end

  test "the member kind needs the member on the badge's team" do
    badge = build_badge("added_by_current_member", team: @other_team)
    assert_not policy(@member, badge, @member).create?
    assert_not policy(@member, badge, nil).new?
  end

  test "team-less self kinds are open to any member, for themselves" do
    SELF_KINDS.each do |permission, needs_team|
      next if needs_team
      badge = build_badge(permission)
      assert policy(@outsider, badge, @outsider).create?, permission
      assert_not policy(@outsider, badge, @member).create?, permission
    end
  end

  test "managers give manager-or-self badges without a team only to the people they manage" do
    badge = build_badge("added_by_manager_or_self")
    assert policy(@manager, badge, @member).create?
    assert policy(@manager, badge, @member).destroy?
    assert policy(@manager, badge, @manager).create?
    assert_not policy(@manager, badge, @outsider).create?
    assert_not policy(@manager, build_badge("added_by_admin_or_self"), @member).create?
    assert_not policy(@manager, build_badge("has_account"), @member).create?
  end

  test "managers of another team don't give a team's manager-or-self badge to people they share" do
    pack = Team.create!(name: "Pack", team_type: team_types(:one))
    Membership.create!(person: @member, team: pack)
    badge = build_badge("added_by_manager_or_self", team: pack)

    assert_not policy(@manager, badge, @member).create?
    assert_not policy(@manager, badge, @member).destroy?
  end

  test "managers see every holder of a badge they manage, including those who left the team" do
    badge = build_badge("added_by_manager", team: @team).tap(&:save!)
    departed = BadgeAssignment.create!(badge: badge, person: @member)
    @member.memberships.destroy_all

    assert BadgeAssignmentPolicy.new(@manager.user, departed).show?
    assert_not BadgeAssignmentPolicy.new(@teammate.user, departed).show?
  end

  test "managers give their team's badges to anyone, except the admin kinds" do
    Badge.permissions.each_key do |permission|
      badge = build_badge(permission, team: @team)
      managed = %w[added_by_manager added_by_manager_or_self added_by_current_member has_account].include?(permission)
      assert_equal managed, policy(@manager, badge, @member).create?, permission
      assert_equal managed, policy(@manager, badge, @member).destroy?, permission
    end
  end

  test "admins give any badge to anyone" do
    Badge.permissions.each_key do |permission|
      assert policy(@admin, build_badge(permission), @outsider).create?, permission
      assert policy(@admin, build_badge(permission), @outsider).destroy?, permission
    end
  end

  test "an update needs the new holder to be one the user may give the badge to" do
    badge = build_badge("added_by_admin_or_self")
    assert policy(@member, badge, @member).update?
    assert_not policy(@member, badge, @teammate).update?
    assert policy(@admin, badge, @teammate).update?
  end

  test "holders are listed to anyone who may see the badge, limited to the people they may see" do
    badge = build_badge("added_by_admin").tap(&:save!)
    mine = BadgeAssignment.create!(badge: badge, person: @member)
    teammates = BadgeAssignment.create!(badge: badge, person: @teammate)
    outsiders = BadgeAssignment.create!(badge: badge, person: @outsider)

    assert BadgeAssignmentPolicy.new(@member.user, badge).index?
    assert_equal [ mine, teammates ].sort_by(&:id), BadgeAssignmentPolicy::Scope.new(@member.user, BadgeAssignment).resolve.where(badge: badge).sort_by(&:id)
    assert BadgeAssignmentPolicy.new(@member.user, mine).show?
    assert_not BadgeAssignmentPolicy.new(@member.user, outsiders).show?
    assert BadgeAssignmentPolicy.new(@admin.user, outsiders).show?

    hidden = build_badge("added_by_admin", team: @other_team)
    assert_not BadgeAssignmentPolicy.new(@member.user, hidden).index?
  end

  private

  def policy(actor, badge, holder)
    BadgeAssignmentPolicy.new(actor.user, BadgeAssignment.new(badge: badge, person: holder))
  end

  def build_badge(permission, team: nil)
    Badge.new(name: "Badge", color: "#000000", short: "B", badge_type: badge_types(:one), team: team, permission: permission)
  end

  def create_person(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.titleize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    person
  end
end
