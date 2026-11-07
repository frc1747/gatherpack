require "test_helper"
require_relative "../support/checklists_count_world"

# Checklists::WrapCommitments (checklists spec §11.1): every commitment, in
# each shape of who owes it, answers who owes, progress, organizers and
# visibility the same after it's wrapped as before.
class ChecklistWrapCommitmentsTest < ActiveSupport::TestCase
  include ChecklistsCountWorld

  setup do
    travel_to Time.zone.parse("2026-10-20 12:00")
    @restore_settings = SettingsTestHelper.apply(feature_badges: "true", commitments_organizers: "Commitment Organizer > Club")
    build_commitments_world
    @volunteer = Badge.create!(name: "Volunteer", short: "V", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)
    @rookie = Badge.create!(name: "Rookie", short: "R", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)
    BadgeAssignment.create!(badge: @volunteer, person: person(:member))
    BadgeAssignment.create!(badge: @volunteer, person: person(:kid))
    BadgeAssignment.create!(badge: @volunteer, person: person(:crew_manager))
    BadgeAssignment.create!(badge: @rookie, person: person(:member2))
    Relationship.create!(parent: person(:organizer), child: person(:member2), relationship_type: @parent_of, created_by: person(:admin))

    @commitments = [
      create_world_commitment("Members owe"),
      create_world_commitment("Club owes, volunteers only", owing_team: @club, owing_badge: @volunteer, exempt_badge: @rookie),
      create_world_commitment("Members owe, volunteers only", owing_badge: @volunteer),
      create_world_commitment("Families owe", group_relationship_type: @parent_of, additional_amount: 1, counts_when: :planned),
      create_world_commitment("Club owes", owing_team: @club, exempt_badge: @rookie, created_by: person(:crew_manager))
    ]
    events = [ create_world_event("Past", "2026-10-11 10:00"), create_world_event("Past 2", "2026-10-12 10:00"), create_world_event("Later", "2026-10-25 10:00") ]
    %i[member kid organizer crew_manager].each { |name| events.each { |event| check_in(name, event) } }
    check_in(:member2, events.first)
    @commitments.each do |commitment|
      commitment.commitment_sources.create!(kind: "checkins", subject: @outreach, max_credits: 3)
      CommitmentOrganizer.create!(commitment: commitment, person: person(:organizer))
      owing = commitment.owing_people.first
      commitment.commitment_adjustments.create!(person: owing, credits: 1, reason: "Raffle") if owing
    end
    @commitments.last.commitment_organizers.find_by(person: person(:crew_manager)).destroy!
  end

  teardown do
    @restore_settings&.call
  end

  test "who owes, progress, organizers and visibility are unchanged for every commitment" do
    with_checklists do
      before = @commitments.to_h { |commitment| [ commitment.title, snapshot(commitment) ] }
      checklists = Checklists::WrapCommitments.new.up

      assert_equal @commitments.size, checklists.size
      @commitments.each do |commitment|
        assert Commitment.find(commitment.id).checklist_item, "#{commitment.title} is wrapped"
        assert_equal before.fetch(commitment.title), snapshot(commitment), commitment.title
      end
    end
  end

  test "the checklist mirrors the commitment and its item counts the same" do
    commitment = @commitments.second
    checklist = Checklists::WrapCommitments.new.up.find { |made| made.title == commitment.title }
    item = checklist.checklist_items.sole

    assert_equal [ @club, Date.new(2026, 10, 1), Date.new(2026, 10, 31), "active", "family" ],
      [ checklist.team, checklist.starts_on, checklist.ends_on, checklist.status, checklist.read_level ]
    assert_equal [ person(:organizer).id ], checklist.checklist_organizers.pluck(:person_id)
    assert_equal [ "count", commitment.id, true, nil ], [ item.kind, item.commitment_id, item.wrapped?, item.read_level ]
    assert_equal({ "base_amount" => 2, "unit" => "shifts", "additional_amount" => 0, "counts_when" => "confirmed" }, item.config)
    assert_equal [ [ "include", "badge" ], [ "exclude", "badge" ] ], checklist.population_rules.map { |rule| [ rule.effect, rule.target_type ] }

    progress = commitment.progress
    Checklists::Evaluator.new(checklist).call.each do |person_id, row|
      next assert(row[item.id].exempt?) unless progress[person_id]

      assert_equal progress[person_id].confirmed, row[item.id].measures["confirmed"]
    end
  end

  test "wrapping twice wraps nothing new, and undoing it keeps every commitment" do
    wrapper = Checklists::WrapCommitments.new
    wrapper.up
    assert_no_difference -> { Checklist.count } do
      assert_empty wrapper.up
    end

    plain = @club.checklists.create!(title: "Unrelated", created_by: person(:admin))
    assert_no_difference -> { Commitment.count } do
      wrapper.down
    end
    assert_equal [ plain.id ], Checklist.ids
    assert_empty ChecklistItem.where.not(commitment_id: nil)
    assert_equal @commitments.size, CommitmentAdjustment.count
    assert_equal @commitments.size, CommitmentSource.count

    assert_equal @commitments.size, wrapper.up.size
  end

  private

  def snapshot(commitment)
    commitment = Commitment.find(commitment.id)
    people = @people.values.sort_by(&:id)
    {
      owing: commitment.owing_people.pluck(:id).sort,
      progress: commitment.progress.transform_values { |progress| [ progress.members.map(&:id), progress.owed, progress.confirmed, progress.planned, progress.met? ] }.sort.to_h,
      period: commitment.period_times,
      organizers: people.map { |viewer| commitment.organizer?(viewer) },
      candidates: people.map { |viewer| commitment.organizer_candidate?(viewer) },
      listed: people.map { |viewer| CommitmentPolicy::Scope.new(viewer.user, Commitment).resolve.exists?(id: commitment.id) },
      shown: people.map { |viewer| [ CommitmentPolicy.new(viewer.user, commitment).show?, CommitmentPolicy.new(viewer.user, commitment).progress? ] },
      seen: people.map { |viewer| commitment.progress_seen_by(viewer)&.members&.map(&:id) },
      profile: people.map { |viewer| people.map { |subject| PersonCommitmentsPolicy.new(viewer.user, subject).visible_commitments.map(&:id).include?(commitment.id) } },
      self_approval: people.map { |viewer| people.map { |subject| commitment.self_or_relative_in_group?(viewer, subject) } }
    }
  end
end
