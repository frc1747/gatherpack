require "test_helper"

class TeamPolicyTest < ActiveSupport::TestCase
  def test_scope
  end

  def test_show
  end

  def test_create
    pack = Team.create!(name: "Pack", team_type: team_types(:one))
    den = Team.create!(name: "Den", team_type: team_types(:one), parent: pack)
    other_den = Team.create!(name: "Other Den", team_type: team_types(:one), parent: pack)
    den_leader = create_person("den-leader@example.com")
    Membership.create!(person: den_leader, team: den, manager: true)
    # Manages another den and is a plain member of the pack.
    other_leader = create_person("other-leader@example.com")
    Membership.create!(person: other_leader, team: other_den, manager: true)
    Membership.create!(person: other_leader, team: pack)
    admin = create_person("admin@example.com", admin: true)

    assert TeamPolicy.new(den_leader.user, Team.new(parent: den)).create?
    assert_not TeamPolicy.new(den_leader.user, Team.new(parent: pack)).create?
    assert_not TeamPolicy.new(den_leader.user, Team.new).create?
    assert_not TeamPolicy.new(other_leader.user, Team.new(parent: pack)).create?
    assert TeamPolicy.new(admin.user, Team.new).create?
  end

  def test_update
  end

  def test_destroy
  end

  def test_show_full
    parent = Team.create!(name: "Club", team_type: team_types(:one))
    child = Team.create!(name: "Students", team_type: team_types(:one), parent: parent)
    grandchild = Team.create!(name: "Class of 2030", team_type: team_types(:one), parent: child)

    parent_manager = create_person("parent-manager@example.com")
    Membership.create!(person: parent_manager, team: parent, manager: true)
    member = create_person("member@example.com")
    Membership.create!(person: member, team: grandchild)
    parent_member = create_person("parent-member@example.com")
    Membership.create!(person: parent_member, team: parent)
    outsider = create_person("outsider@example.com")

    assert TeamPolicy.new(parent_manager.user, child).show_full?
    assert TeamPolicy.new(parent_manager.user, grandchild).show_full?
    assert TeamPolicy.new(member.user, grandchild).show_full?
    assert_not TeamPolicy.new(parent_member.user, child).show_full?
    assert_not TeamPolicy.new(outsider.user, child).show_full?
  end

  private

  def create_person(email, admin: false)
    user = User.create!(email: email, password: "Password1!", admin: admin)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
  end
end
