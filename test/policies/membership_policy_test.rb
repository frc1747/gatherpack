require "test_helper"

class MembershipPolicyTest < ActiveSupport::TestCase
  setup do
    @member = users(:one) # person one, a plain member of team one
    @team = teams(:one)
    @open_team = teams(:two)
    @open_team.update!(join_permission: :has_account)
  end

  def allowed?(user, attrs)
    MembershipPolicy.new(user, Membership.new(attrs)).create?
  end

  def test_create_rejects_a_member_promoting_themselves
    refute allowed?(@member, team: @team, person: people(:one), manager: true)
  end

  def test_create_rejects_a_member_adding_someone_else
    refute allowed?(@member, team: @team, person: people(:two))
  end

  def test_create_allows_joining_an_open_team
    assert allowed?(@member, team: @open_team, person: people(:one))
  end

  def test_create_rejects_joining_an_open_team_as_manager
    refute allowed?(@member, team: @open_team, person: people(:one), manager: true)
  end

  def test_create_rejects_adding_someone_else_to_an_open_team
    refute allowed?(@member, team: @open_team, person: people(:two))
  end

  def test_create_allows_team_managers_to_add_people_they_manage
    memberships(:one).update!(manager: true)
    sub_team = Team.create!(name: "Sub", team_type: team_types(:one), parent: @team)
    Membership.create!(person: people(:two), team: sub_team)
    assert allowed?(@member, team: @team, person: people(:two), manager: true)
  end

  def test_create_rejects_team_managers_adding_people_they_dont_manage
    memberships(:one).update!(manager: true)
    refute allowed?(@member, team: @team, person: people(:two))
  end

  def test_create_rejects_team_managers_adding_to_a_team_they_dont_manage
    memberships(:one).update!(manager: true)
    closed_team = Team.create!(name: "Closed", team_type: team_types(:one))
    refute allowed?(@member, team: closed_team, person: people(:one))
  end

  def test_create_allows_admins
    @member.update!(admin: true)
    assert allowed?(@member, team: @open_team, person: people(:two), manager: true)
  end
end
