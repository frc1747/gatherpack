require "test_helper"

# A team badge needs its holder in the badge's team. Every way of leaving the
# team takes the badge away; badges the holder still qualifies for stay.
class BadgeAssignmentTeamMembershipTest < ActiveSupport::TestCase
  setup do
    @pack = Team.create!(name: "Pack", team_type: team_types(:one))
    @den_a = Team.create!(name: "Den A", team_type: team_types(:one), parent: @pack)
    @den_b = Team.create!(name: "Den B", team_type: team_types(:one), parent: @pack)
    @person = Person.create!(first_name: "Ann", last_name: "Test")
    @membership = Membership.create!(person: @person, team: @den_a)
    @den_a_badge = create_badge("Den A Helper", @den_a)
    @pack_badge = create_badge("Pack Helper", @pack)
    @open_badge = create_badge("First Aid", nil)
    [ @den_a_badge, @pack_badge, @open_badge ].each { |badge| BadgeAssignment.create!(badge: badge, person: @person) }
  end

  def create_badge(name, team)
    Badge.create!(name: name, short: name.first(2), color: "#336699", badge_type: badge_types(:one), team: team)
  end

  def held_badges
    @person.reload.badges.to_a
  end

  test "leaving the team removes its badges and keeps the rest" do
    Membership.create!(person: @person, team: @den_b)
    @membership.destroy!

    assert_equal [ @open_badge, @pack_badge ].sort_by(&:name), held_badges.sort_by(&:name)
  end

  test "leaving every team removes the badges of the teams above it too" do
    @membership.destroy!

    assert_equal [ @open_badge ], held_badges
  end

  test "the removal is in the audit log" do
    @membership.destroy!

    assert AuditLog.where(item_type: "BadgeAssignment", event: "destroy").exists?
  end

  test "moving a membership to another team removes the old team's badges" do
    @membership.update!(team: @den_b)

    assert_not_includes held_badges, @den_a_badge
    assert_includes held_badges, @pack_badge
  end

  test "moving a membership to another person removes the first person's team badges" do
    other = Person.create!(first_name: "Bo", last_name: "Test")
    @membership.update!(person: other)

    assert_equal [ @open_badge ], held_badges
  end

  test "a manager who steps down loses the badges of the teams below" do
    leader = Person.create!(first_name: "Lee", last_name: "Test")
    Membership.create!(person: leader, team: @pack, manager: true)
    BadgeAssignment.create!(badge: @den_a_badge, person: leader)

    leader.memberships.first.update!(manager: false)

    assert_not_includes leader.reload.badges, @den_a_badge
  end

  test "removing a team from a person's teams removes its badges" do
    @person.team_ids = [ @den_b.id ]

    assert_not_includes held_badges, @den_a_badge
    assert_includes held_badges, @pack_badge
  end

  test "removing a person from a team's people removes its badges" do
    @den_a.person_ids = []

    assert_equal [ @open_badge ], held_badges
  end

  test "moving a team out from under another removes the other team's badges" do
    @den_a.update!(parent: nil)

    assert_equal [ @den_a_badge, @open_badge ].sort_by(&:name), held_badges.sort_by(&:name)
  end

  test "moving a team away from a manager above it removes its badges from that manager" do
    leader = Person.create!(first_name: "Lee", last_name: "Test")
    Membership.create!(person: leader, team: @pack, manager: true)
    BadgeAssignment.create!(badge: @den_a_badge, person: leader)

    @den_a.update!(parent: nil)

    assert_not_includes leader.reload.badges, @den_a_badge
  end

  test "deleting a team above removes its badges from the members below" do
    org = Team.create!(name: "Org", team_type: team_types(:one))
    @pack.update!(parent: org)
    org_badge = create_badge("Org Helper", org)
    BadgeAssignment.create!(badge: org_badge, person: @person)
    pack_child = Team.create!(name: "Pack Committee", team_type: team_types(:one), parent: @pack)

    @pack.destroy!

    assert_not_includes held_badges, org_badge
    assert Team.exists?(pack_child.id)
  end

  test "deleting the badge's own team removes the badge from its holders" do
    @den_a.destroy!

    assert_not BadgeAssignment.exists?(badge: @den_a_badge, person: @person)
    assert Badge.exists?(@den_a_badge.id)
  end

  test "a merge that moves the badge to the kept person before commit keeps it" do
    kept = Person.create!(first_name: "Ann", last_name: "Kept")
    Membership.create!(person: kept, team: @den_a)

    # A merge removes the duplicate membership, then moves the rest over.
    ActiveRecord::Base.transaction do
      @membership.destroy!
      BadgeAssignment.where(person_id: @person.id).update_all(person_id: kept.id)
    end

    assert_includes kept.reload.badges, @den_a_badge
    assert_includes kept.badges, @pack_badge
  end

  test "a failed badge removal keeps the person in the team" do
    Hook.create!(name: "Fails", event: "badge_assignments - destroy", code: "raise 'hook failed'")

    assert_raises(RuntimeError) { @membership.destroy! }

    assert Membership.exists?(@membership.id)
    assert_includes held_badges, @den_a_badge
  end

  test "a failed badge removal keeps the team on the person" do
    Hook.create!(name: "Fails", event: "badge_assignments - destroy", code: "raise 'hook failed'")

    assert_raises(RuntimeError) { @person.team_ids = [ @den_b.id ] }

    assert_equal [ @den_a ], @person.reload.teams.to_a
    assert_includes held_badges, @den_a_badge
  end

  test "moving a badge to another team removes it from holders outside that team" do
    holder = Person.create!(first_name: "Bo", last_name: "Test")
    Membership.create!(person: holder, team: @den_b)
    BadgeAssignment.create!(badge: @pack_badge, person: holder)

    @pack_badge.update!(team: @den_b)

    assert_not_includes held_badges, @pack_badge
    assert_includes holder.reload.badges, @pack_badge
  end

  test "giving a team-less badge a team removes it from holders outside that team" do
    @open_badge.update!(team: @den_b)

    assert_not_includes held_badges, @open_badge
  end

  test "deleting a person doesn't fail on their team badges" do
    assert_difference -> { BadgeAssignment.count }, -3 do
      @person.destroy!
    end
  end

  test "the cleanup removes team badges already held outside the team" do
    Membership.where(id: @membership.id).delete_all
    other = Person.create!(first_name: "Bo", last_name: "Test")
    Membership.create!(person: other, team: @den_a)
    kept = BadgeAssignment.create!(badge: @den_a_badge, person: other)

    require Rails.root.join("db/migrate/20261115120000_remove_team_badges_outside_their_team").to_s
    ActiveRecord::Migration.suppress_messages { RemoveTeamBadgesOutsideTheirTeam.new.migrate(:up) }

    assert_equal [ @open_badge ], held_badges
    assert BadgeAssignment.exists?(kept.id)
  end

  test "the cleanup removes the badges of a team that was deleted" do
    Membership.where(team: @den_a).delete_all
    Team.where(id: @den_a.id).delete_all

    require Rails.root.join("db/migrate/20261115120000_remove_team_badges_outside_their_team").to_s
    ActiveRecord::Migration.suppress_messages { RemoveTeamBadgesOutsideTheirTeam.new.migrate(:up) }

    assert_not BadgeAssignment.exists?(badge: @den_a_badge)
    assert_includes held_badges, @open_badge
    ActiveRecord::Migration.suppress_messages { RemoveTeamBadgesOutsideTheirTeam.new.migrate(:down) }
  end
end
