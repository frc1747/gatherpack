require "test_helper"

class ApplicationPolicyTest < ActiveSupport::TestCase
  setup do
    # Pack
    # ├── Den A (run by @den_leader)
    # │   └── Patrol
    # └── Den B
    # Other Org (unrelated)
    @pack = Team.create!(name: "Pack", team_type: team_types(:one))
    @den_a = Team.create!(name: "Den A", team_type: team_types(:one), parent: @pack)
    @patrol = Team.create!(name: "Patrol", team_type: team_types(:one), parent: @den_a)
    @den_b = Team.create!(name: "Den B", team_type: team_types(:one), parent: @pack)
    @other_org = Team.create!(name: "Other Org", team_type: team_types(:one))

    @den_leader_user = User.create!(email: "den-leader@example.com", password: "Password1!")
    @den_leader = Person.create!(user: @den_leader_user, first_name: "Dana", last_name: "Leader")
    Membership.create!(person: @den_leader, team: @den_a, manager: true)
  end

  # --- teams --------------------------------------------------------------

  test "a manager manages their own team" do
    assert manages?(@den_leader_user, @den_a)
  end

  test "a manager manages a descendant of their team" do
    assert manages?(@den_leader_user, @patrol)
  end

  test "a manager does not manage an ancestor of their team" do
    assert_not manages?(@den_leader_user, @pack)
  end

  test "a manager does not manage a sibling of their team" do
    assert_not manages?(@den_leader_user, @den_b)
  end

  test "a manager does not manage an unrelated team" do
    assert_not manages?(@den_leader_user, @other_org)
  end

  test "a plain member does not manage their team" do
    member_user, = create_person("member", team: @den_a)
    assert_not manages?(member_user, @den_a)
  end

  # --- people -------------------------------------------------------------

  test "a manager manages a member of their team" do
    _, member = create_person("member", team: @den_a)
    assert manages?(@den_leader_user, member)
  end

  test "a manager manages a member of a descendant team" do
    _, member = create_person("patrol-member", team: @patrol)
    assert manages?(@den_leader_user, member)
  end

  test "a manager does not manage an admin who is a member of their team" do
    _, admin = create_person("admin", team: @den_a, admin: true)
    assert_not manages?(@den_leader_user, admin)
  end

  test "a manager does not manage an architect who is a member of their team" do
    _, architect = create_person("architect", team: @den_a, architect: true)
    assert_not manages?(@den_leader_user, architect)
  end

  test "a manager does not manage the manager of their parent team" do
    _, pack_leader = create_person("pack-leader", team: @pack, manager: true)
    assert_not manages?(@den_leader_user, pack_leader)
  end

  test "a manager does not manage the parent team's manager even when they're a member of the team" do
    _, pack_leader = create_person("pack-leader", team: @pack, manager: true)
    Membership.create!(person: pack_leader, team: @den_a, manager: false)
    assert_not manages?(@den_leader_user, pack_leader)
  end

  test "the manager of a parent team manages the manager of a sub-team" do
    pack_leader_user, = create_person("pack-leader", team: @pack, manager: true)
    assert manages?(pack_leader_user, @den_leader)
  end

  test "co-managers of a team manage each other" do
    co_leader_user, co_leader = create_person("co-leader", team: @den_a, manager: true)
    assert manages?(@den_leader_user, co_leader)
    assert manages?(co_leader_user, @den_leader)
  end

  test "a manager manages the manager of a descendant team" do
    _, patrol_leader = create_person("patrol-leader", team: @patrol, manager: true)
    assert manages?(@den_leader_user, patrol_leader)
  end

  test "a manager does not manage a member of a sibling or unrelated team" do
    _, den_b_member = create_person("den-b-member", team: @den_b)
    _, outsider = create_person("outsider", team: @other_org)
    assert_not manages?(@den_leader_user, den_b_member)
    assert_not manages?(@den_leader_user, outsider)
  end

  test "a manager does not manage someone with no team" do
    _, loner = create_person("loner")
    assert_not manages?(@den_leader_user, loner)
  end

  # --- other records ------------------------------------------------------

  test "a manager manages a record that belongs to a team they manage" do
    assert manages?(@den_leader_user, Event.new(team: @patrol))
    assert_not manages?(@den_leader_user, Event.new(team: @pack))
  end

  test "a record without a team is not managed" do
    assert_not manages?(@den_leader_user, Event.new)
    assert_not manages?(@den_leader_user, nil)
  end

  # --- no person ----------------------------------------------------------

  test "a user without a person manages nothing" do
    user = User.create!(email: "no-person@example.com", password: "Password1!")
    _, member = create_person("member", team: @den_a)
    assert_not manages?(user, @den_a)
    assert_not manages?(user, member)
  end

  # --- not a policy action ------------------------------------------------

  test "manages? can't be called as a policy action" do
    assert_not ApplicationPolicy.new(@den_leader_user, @den_a).respond_to?(:manages?)
  end

  private

  def manages?(user, record)
    ApplicationPolicy.new(user, record).send(:manages?, record)
  end

  def create_person(name, team: nil, manager: false, admin: false, architect: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin, architect: architect)
    person = Person.create!(user: user, first_name: name.titleize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    [ user, person ]
  end
end
