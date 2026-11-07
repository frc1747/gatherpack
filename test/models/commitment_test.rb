require "test_helper"
require_relative "../support/commitments_world"

class CommitmentTest < ActiveSupport::TestCase
  include CommitmentsWorld

  setup do
    build_commitments_world
  end

  test "the owing team and those below it owe, narrowed by the owing badge" do
    commitment = create_world_commitment(owing_team: @club)
    assert_includes commitment.owing_people, person(:member)
    assert_includes commitment.owing_people, person(:organizer)
    assert_not commitment.covers?(person(:outsider))
    assert_not commitment.covers?(person(:admin))

    badge = Badge.create!(name: "Volunteer", short: "V", color: "#000000", badge_type: badge_types(:one), permission: :added_by_admin)
    BadgeAssignment.create!(badge: badge, person: person(:member2))
    commitment.update!(owing_badge: badge)
    assert_equal [ person(:member2) ], commitment.owing_people.to_a
  end

  test "the owing badge can't be deleted out from under a commitment" do
    badge = Badge.create!(name: "Volunteer", short: "V", color: "#000000", badge_type: badge_types(:one), permission: :added_by_admin)
    BadgeAssignment.create!(badge: badge, person: person(:member2))
    commitment = create_world_commitment(owing_badge: badge)

    assert_not badge.destroy
    assert_equal [ "Cannot delete record because dependent owing commitments exist" ], badge.errors.full_messages
    assert_raises(ActiveRecord::RecordNotDestroyed) { badge.reload.destroy! }
    assert_equal badge, commitment.reload.owing_badge
    assert_equal [ person(:member2) ], commitment.owing_people.to_a
  end

  test "a commitment's team and owing team can't be deleted" do
    commitment = create_world_commitment(team: @club, owing_team: @members)

    assert_not @members.destroy
    assert_equal [ "Cannot delete record because dependent owed commitments exist" ], @members.errors.full_messages
    assert_raises(ActiveRecord::RecordNotDestroyed) { @club.reload.destroy! }
    assert_includes @club.errors.full_messages, "Cannot delete record because dependent commitments exist"
    assert_equal [ @club, @members ], [ commitment.reload.team, commitment.owing_team ]
  end

  test "validates the period, amount and that the owing team is in reach" do
    commitment = Commitment.new(title: "Bad", team: @members, owing_team: @club, base_amount: 0, unit: "shifts",
      starts_on: Date.new(2026, 10, 2), ends_on: Date.new(2026, 10, 1))
    assert_not commitment.valid?
    assert commitment.errors[:ends_on].any?
    assert commitment.errors[:base_amount].any?
    assert_includes commitment.errors[:owing_team_id], "must be Members or a team below it"
  end

  test "the creator is its first organizer" do
    commitment = create_world_commitment(created_by: person(:organizer))
    assert_equal [ person(:organizer) ], commitment.organizers.to_a
  end

  test "organizer grants reach their teams up to the highest team, and below" do
    with_organizer_grants("Commitment Organizer > Club") do
      ids = Commitment.creatable_team_ids(person(:organizer))
      assert_includes ids, @crew.id
      assert_includes ids, @club.id
      assert_not_includes ids, @org.id
      assert_not_includes ids, @members.id
    end
    with_organizer_grants("") do
      assert_empty Commitment.creatable_team_ids(person(:organizer))
    end
    assert_equal Team.ids.sort, Commitment.creatable_team_ids(person(:admin)).sort
    assert_includes Commitment.creatable_team_ids(person(:crew_manager)), @crew.id
  end

  test "a listed organizer runs it only while their grant reaches its team" do
    commitment = create_world_commitment
    with_organizer_grants("Commitment Organizer > Club") do
      commitment.commitment_organizers.create!(person: person(:organizer))
      assert commitment.organizer?(person(:organizer))
    end
    assert_not commitment.organizer?(person(:organizer))
    assert commitment.organizer?(person(:admin))
    assert_not commitment.organizer?(person(:crew_manager)), "manages Crew, not Club"
  end

  test "only grant holders can be added as organizers" do
    commitment = create_world_commitment
    with_organizer_grants("Commitment Organizer > Club") do
      assert_not commitment.commitment_organizers.build(person: person(:member)).valid?
      assert commitment.commitment_organizers.build(person: person(:organizer)).valid?
    end
  end

  test "self or relative covers the organizer and anyone related to them" do
    commitment = create_world_commitment
    assert commitment.self_or_relative?(person(:organizer), person(:organizer))
    assert commitment.self_or_relative?(person(:organizer), person(:kid))
    assert commitment.self_or_relative?(person(:kid), person(:organizer))
    assert_not commitment.self_or_relative?(person(:organizer), person(:member))
  end

  test "the initializer registers the setting, hook events and the check-in kind" do
    assert_equal Commitments::CheckinSource, Commitments.source_kind(:checkins)
    assert_equal "Commitments", Settings.get(:commitments_organizers).group
    assert_includes GatherPack::HookCatalog.targets, "commitment_adjustments"
    assert GatherPack::Features.all.find { |feature| feature.key == :commitments }.default_enabled == false
  end
end
