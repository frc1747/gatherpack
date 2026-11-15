require "test_helper"

class BadgePolicyTest < ActiveSupport::TestCase
  setup do
    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @admin = create_person("admin", admin: true)
    @manager = create_person("manager", team: @team, manager: true)
    @member = create_person("member", team: @team)
  end

  test "admins manage every badge" do
    Badge.permissions.each_key do |permission|
      [ @team, nil ].each do |team|
        badge = build_badge(permission, team: team)
        assert BadgePolicy.new(@admin.user, badge).update?, "#{permission}, team #{team.inspect}"
        assert BadgePolicy.new(@admin.user, badge).destroy?, "#{permission}, team #{team.inspect}"
      end
    end
  end

  test "managers manage their team's badges except the admin kinds" do
    managed = %w[added_by_manager added_by_manager_or_self added_by_current_member has_account]
    Badge.permissions.each_key do |permission|
      badge = build_badge(permission, team: @team)
      assert_equal managed.include?(permission), BadgePolicy.new(@manager.user, badge).update?, permission
      assert_equal managed.include?(permission), BadgePolicy.new(@manager.user, badge).destroy?, permission
    end
  end

  test "managers don't manage badges without a team or of other teams" do
    other_team = Team.create!(name: "Den B", team_type: team_types(:one))
    %w[added_by_manager_or_self has_account added_by_admin_or_self].each do |permission|
      assert_not BadgePolicy.new(@manager.user, build_badge(permission)).update?, permission
    end
    assert_not BadgePolicy.new(@manager.user, build_badge("added_by_manager", team: other_team)).update?
  end

  test "members never manage a badge, even one they may take" do
    Badge.permissions.each_key do |permission|
      [ @team, nil ].each do |team|
        badge = build_badge(permission, team: team)
        assert_not BadgePolicy.new(@member.user, badge).update?, "#{permission}, team #{team.inspect}"
        assert_not BadgePolicy.new(@member.user, badge).destroy?, "#{permission}, team #{team.inspect}"
      end
    end
  end

  private

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
