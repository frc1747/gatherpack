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
    admin = create_person("admin@example.com", admin: true)
    architect = create_person("architect@example.com", admin: true, architect: true)
    other_architect = create_person("other-architect@example.com", admin: true, architect: true)
    member = create_person("member@example.com")

    assert UserPolicy.new(admin.user, member.user).update?
    assert UserPolicy.new(admin.user, admin.user).update?
    assert_not UserPolicy.new(admin.user, architect.user).update?
    assert UserPolicy.new(architect.user, architect.user).update?
    assert UserPolicy.new(architect.user, other_architect.user).update?
    assert_not UserPolicy.new(member.user, architect.user).update?
  end

  def test_update_by_a_manager
    pack = Team.create!(name: "Pack", team_type: team_types(:one))
    den = Team.create!(name: "Den", team_type: team_types(:one), parent: pack)
    pack_leader = create_person("pack-leader@example.com")
    Membership.create!(person: pack_leader, team: pack, manager: true)
    den_leader = create_person("den-leader@example.com")
    Membership.create!(person: den_leader, team: den, manager: true)
    admin = create_person("admin@example.com", admin: true)
    Membership.create!(person: admin, team: den)
    member = create_person("member@example.com")
    Membership.create!(person: member, team: den)

    assert UserPolicy.new(den_leader.user, den_leader.user).update?
    assert_not UserPolicy.new(den_leader.user, admin.user).update?
    assert_not UserPolicy.new(den_leader.user, pack_leader.user).update?
    assert_not UserPolicy.new(den_leader.user, member.user).update?
    assert_not UserPolicy.new(pack_leader.user, den_leader.user).update?
  end

  def test_destroy
  end

  private

  def create_person(email, admin: false, architect: false)
    user = User.create!(email: email, password: "Password1!", admin: admin, architect: architect)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
  end
end
