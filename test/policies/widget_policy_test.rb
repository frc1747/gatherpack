require "test_helper"

class WidgetPolicyTest < ActiveSupport::TestCase
  setup do
    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @member = User.create!(email: "member@example.com", password: "Password1!")
    Membership.create!(person: Person.create!(user: @member, first_name: "Mem", last_name: "Ber"), team: @team)
    @admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)

    @everyone = Widget.create!(title: "Everyone")
    @team_only = Widget.create!(title: "Team", viewer: "team", team: @team)
    @admin_only = Widget.create!(title: "Admins", viewer: "admin")
    @disabled = Widget.create!(title: "Off", enabled: false)
  end

  test "everyone signed in can list and view widgets they can see; only admins manage them" do
    assert WidgetPolicy.new(@member, Widget).index?
    assert_not WidgetPolicy.new(nil, Widget).index?
    assert WidgetPolicy.new(@member, @team_only).show?
    assert_not WidgetPolicy.new(@member, @admin_only).show?
    assert WidgetPolicy.new(@admin, @everyone).update?
    assert_not WidgetPolicy.new(@member, Widget.new).create?
    assert_not WidgetPolicy.new(@member, @everyone).update?
    assert_not WidgetPolicy.new(@member, @everyone).destroy?
  end

  test "the scope is the widgets a person can see" do
    assert_equal [ @everyone, @team_only ].sort_by(&:title), WidgetPolicy::Scope.new(@member, Widget).resolve.sort_by(&:title)
    assert_equal 4, WidgetPolicy::Scope.new(@admin, Widget).resolve.count
    assert_empty WidgetPolicy::Scope.new(nil, Widget).resolve
  end

  test "body follows visibility" do
    assert WidgetPolicy.new(@member, @team_only).body?
    assert_not WidgetPolicy.new(@member, @admin_only).body?
    assert_not WidgetPolicy.new(@member, @disabled).body?
  end
end
