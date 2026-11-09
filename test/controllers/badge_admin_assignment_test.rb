require "test_helper"

# Person field grants (and other features) trust "added_by_admin" to mean an
# admin chose the badge's holders, so only admins make those badges, hand
# them out, or place badges on teams they don't manage.
class BadgeAdminAssignmentTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @team = Team.create!(name: "Robotics", team_type: team_types(:one))
    @other_team = Team.create!(name: "Drama", team_type: team_types(:one))
    @manager = create_person("lead@example.com")
    Membership.create!(person: @manager, team: @team, manager: true)
    @student = create_person("student@example.com")
    Membership.create!(person: @student, team: @team)
    @admin = create_person("admin@example.com", admin: true)
  end

  test "a manager can't create an admin-only badge and hold it" do
    sign_in @manager.user
    assert_no_difference -> { Badge.count } do
      post badges_path, params: { badge: badge_attributes("Treasurer", team_id: @team.id, permission: "added_by_admin", person_ids: [ @manager.id ]) }
    end
    assert_redirected_to root_path
    assert_equal "You are not allowed to do that", flash[:notice]
  end

  test "a manager can't create an admin-only badge even without holders" do
    sign_in @manager.user
    assert_no_difference -> { Badge.count } do
      post badges_path, params: { badge: badge_attributes("Treasurer", team_id: @team.id, permission: "added_by_admin") }
    end
  end

  test "a manager can't get an admin-only badge by sending a malformed permission" do
    sign_in @manager.user
    [ [ "x" ], { "a" => "b" } ].each do |permission|
      post badges_path, params: { badge: badge_attributes("Treasurer", team_id: @team.id, permission: permission, person_ids: [ @manager.id ]) }
    end

    assert_not Badge.added_by_admin.exists?(name: "Treasurer")
    assert_not BadgeAssignment.joins(:badge).exists?(badges: { name: "Treasurer" }, person_id: @manager.id)
  end

  test "an array team changes nothing about the team and never reaches SQL as a fragment" do
    badge = create_badge("Pit Crew", permission: :added_by_manager, team: @team)
    sign_in @manager.user
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      patch badge_path(badge), params: { badge: { name: "Renamed", team_id: [ "1=1" ] } }
    end

    assert_equal @team.id, badge.reload.team_id
    assert_not queries.any? { |sql| sql.include?("1=1") }, "a request value reached SQL as a fragment"
  end

  test "a manager can't move a team badge they manage to a team they don't manage" do
    badge = create_badge("Pit Crew", permission: :added_by_manager, team: @team)
    sign_in @manager.user

    patch badge_path(badge), params: { badge: { team_id: @other_team.id } }

    assert_equal @team.id, badge.reload.team_id
  end

  test "a manager can't make a team badge admin-only" do
    badge = create_badge("Pit Crew", permission: :added_by_manager, team: @team)
    sign_in @manager.user

    patch badge_path(badge), params: { badge: { permission: "added_by_admin", person_ids: [ @manager.id ] } }

    assert badge.reload.added_by_manager?
    assert_not badge.people.include?(@manager)
  end

  test "a manager still creates and edits manager badges for their team" do
    sign_in @manager.user
    post badges_path, params: { badge: badge_attributes("Pit Crew", team_id: @team.id, permission: "added_by_manager", person_ids: [ @student.id ]) }
    badge = Badge.find_by!(name: "Pit Crew")
    assert badge.added_by_manager?
    assert_equal [ @student ], badge.people.to_a

    patch badge_path(badge), params: { badge: { name: "Pit Crew Leads", team_id: @team.id, permission: "added_by_manager", person_ids: [ @student.id, @manager.id ] } }
    assert_equal "Pit Crew Leads", badge.reload.name
    assert_equal @team.id, badge.team_id
    assert_equal 2, badge.people.count
  end

  test "an admin creates and edits admin badges and their holders" do
    sign_in @admin.user
    post badges_path, params: { badge: badge_attributes("Treasurer", team_id: "", permission: "added_by_admin", person_ids: [ @manager.id ]) }
    badge = Badge.find_by!(name: "Treasurer")
    assert badge.added_by_admin?
    assert_equal [ @manager ], badge.people.to_a

    patch badge_path(badge), params: { badge: { team_id: @team.id, person_ids: [ @student.id ] } }
    assert_equal @team.id, badge.reload.team_id
    assert_equal [ @student ], badge.people.to_a
  end

  private

  def create_person(email, admin: false)
    user = User.create!(email: email, password: "Password1!", admin: admin)
    Person.create!(user: user, first_name: "Test", last_name: email.split("@").first.capitalize)
  end

  def create_badge(name, permission:, team: nil)
    Badge.create!(name: name, short: name.first(3), color: "#336699", badge_type: badge_types(:one), team: team, permission: permission)
  end

  def badge_attributes(name, **attributes)
    { name: name, short: name.first(3), color: "#000000", badge_type_id: badge_types(:one).id, **attributes }
  end
end
