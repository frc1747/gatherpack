require "test_helper"

class UserPolicyTest < ActiveSupport::TestCase
  def test_scope
  end

  def test_show
  end

  def test_create
    admin = create_person("admin@example.com", admin: true)
    member = create_person("member@example.com")
    manager = create_person("manager@example.com")
    team = Team.create!(name: "Den", team_type: team_types(:one))
    Membership.create!(person: manager, team: team, manager: true)
    Membership.create!(person: member, team: team)

    assert UserPolicy.new(admin.user, User.new).create?
    assert UserPolicy.new(admin.user, User.new).new?
    assert_not UserPolicy.new(member.user, User.new).create?
    assert_not UserPolicy.new(member.user, User.new).new?
    assert_not UserPolicy.new(manager.user, User.new).create?
  end

  def test_update
  end

  def test_destroy
  end

  private

  def create_person(email, admin: false)
    user = User.create!(email: email, password: "Password1!", admin: admin)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
  end
end
