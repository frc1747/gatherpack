require "test_helper"
require_relative "../support/checklists_count_world"

# Checklists::WrapCommitments (checklists spec §11.1): every commitment, in
# each shape of who owes it, answers who owes, progress, organizers and
# visibility the same after it's wrapped as before, and the checklist shows
# each person's count to exactly the people the commitment pages did.
#
# Besides the commitments world: dad is "Parent of" member (no
# guardianship), guardian is member2's guardian, lead manages Members (below
# the commitments' team), and lapsed was an organizer until their organizer
# badge was taken away.
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
    @people[:dad] = create_world_person("Dad")
    Relationship.create!(parent: person(:dad), child: person(:member), relationship_type: @parent_of, created_by: person(:admin))
    @people[:guardian] = create_world_person("Guardian")
    guardian_of = RelationshipType.create!(parent_label: "Guardian of", child_label: "Ward of", permission: :added_by_admin, guardianship: :minor)
    person(:member2).update!(birthday: Date.new(2014, 3, 1))
    Relationship.create!(parent: person(:guardian), child: person(:member2), relationship_type: guardian_of, created_by: person(:admin))
    @people[:lead] = create_world_person("Lead", @members, manager: true)
    @people[:lapsed] = create_world_person("Lapsed", @crew)
    lapsed_badge = BadgeAssignment.create!(badge: @organizer_badge, person: person(:lapsed))

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
      CommitmentOrganizer.create!(commitment: commitment, person: person(:lapsed))
      owing = commitment.owing_people.first
      commitment.commitment_adjustments.create!(person: owing, credits: 1, reason: "Raffle") if owing
    end
    @commitments.last.commitment_organizers.find_by(person: person(:crew_manager)).destroy!
    lapsed_badge.destroy!
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
        assert_checklist_shows_as_before(commitment, before.fetch(commitment.title))
      end
    end
  end

  test "the wrapper's levels are the count defaults; the pooled parent, the guardian and the lead are the cases that differ from them" do
    with_checklists do
      Checklists::WrapCommitments.new.up
      pooled = Commitment.find(@commitments.fourth.id).checklist_item
      alone = Commitment.find(@commitments.first.id).checklist_item

      assert_equal [ "self_and_leaders", "group" ], [ pooled.checklist.read_level, pooled.read_level ]
      assert_equal [ "self_and_leaders", "self_and_leaders" ], [ alone.checklist.read_level, alone.read_level ]

      member = person(:member).id
      dad = Checklists::Visibility.new(pooled.checklist, person(:dad)).prepare([ member ])
      assert_equal [ :full, :full ], [ dad.access(pooled, member), dad.access(nil, member) ], "a parent without guardianship sees the pooled count"
      assert_includes Checklists.checklist_for(person(:member), viewer: person(:dad)).map(&:first), pooled.checklist

      member2 = person(:member2).id
      guardian = Checklists::Visibility.new(alone.checklist, person(:guardian)).prepare([ member2 ])
      assert_equal [ nil, nil ], [ guardian.access(alone, member2), guardian.access(nil, member2) ], "a guardian doesn't see an unpooled count"
      lead = Checklists::Visibility.new(alone.checklist, person(:lead)).prepare([ member2 ])
      assert_equal [ nil, nil ], [ lead.access(alone, member2), lead.access(nil, member2) ], "a leader who doesn't run it doesn't see it"
    end
  end

  test "a guardian or leader with nobody to see on a wrapped checklist doesn't get it listed; a plain checklist still lists" do
    with_checklists do
      Checklists::WrapCommitments.new.up
      alone = Commitment.find(@commitments.first.id).checklist_item.checklist
      volunteers = Commitment.find(@commitments.third.id).checklist_item.checklist
      listed = ->(name) { ChecklistPolicy::Scope.new(person(name).user, Checklist).resolve }

      assert_not_includes listed.(:guardian), alone
      assert_not_includes listed.(:lead), volunteers, "the lead manages Members but doesn't run it or hold the badge"
      assert_includes listed.(:lead), alone, "the lead is a member of Members, so owes it"
      assert_includes listed.(:member2), alone, "member2 owes it"
      assert_includes listed.(:organizer), alone

      BadgeAssignment.create!(badge: @rookie, person: person(:guardian))
      ChecklistGrant.create!(checklist: alone, badge: @rookie)
      assert_includes listed.(:guardian), alone, "a grant still opens it"
      assert ChecklistPolicy.new(person(:guardian).user, alone).show?
      plain = Checklist.create!(team: @members, title: "Plain", status: :active, created_by: person(:admin))
      plain.checklist_results.create!(person: person(:member2), item: nil, status: :not_met, computed_at: Time.current)
      assert_includes listed.(:guardian), plain, "a guardian sees their ward's plain checklist"
    end
  end

  test "an item added to a wrapped checklist lists it to whoever that item reaches, and the count stays hidden from them" do
    with_checklists do
      Checklists::WrapCommitments.new.up
      alone = Commitment.find(@commitments.first.id).checklist_item.checklist
      volunteers = Commitment.find(@commitments.third.id).checklist_item.checklist
      added = [ alone, volunteers ].to_h do |checklist|
        badge = checklist.checklist_items.new(kind: "badge", label: "Medical form", read_level: "family")
        badge.config_params = { badge_ids: [ @rookie.id ] }
        badge.save!
        Checklists::Refresher.new(checklist.reload, silent: true).call
        [ checklist, badge ]
      end

      [ [ :guardian, alone, :member2 ], [ :lead, volunteers, :member ] ].each do |name, checklist, subject|
        viewer = person(name)
        count = checklist.checklist_items.find_by(wrapped: true)
        id = person(subject).id
        visibility = Checklists::Visibility.new(checklist, viewer).prepare([ id ])

        assert_includes ChecklistPolicy::Scope.new(viewer.user, Checklist).resolve, checklist, "#{name}: listed through the medical form"
        assert ChecklistPolicy.new(viewer.user, checklist).show?, name
        assert_equal :full, visibility.access(added[checklist], id), "#{name} sees #{subject}'s medical form"
        assert_equal [ nil, nil ], [ visibility.access(count, id), visibility.access(nil, id) ], "#{name}: the count and overall stay hidden"
      end
    end
  end

  test "organizers keep running a wrapped checklist once checklists_organizers names a different badge" do
    with_checklists do
      Checklists::WrapCommitments.new.up
      wrapped = Commitment.find(@commitments.first.id).checklist_item.checklist
      plain = Checklist.create!(team: @club, title: "Plain", status: :active, created_by: person(:admin))
      ChecklistOrganizer.new(checklist: plain, person: person(:organizer)).save!(validate: false)
      Badge.create!(name: "Checklist Organizer", short: "CO", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)
      with_settings(checklists_organizers: "Checklist Organizer") do
        organizer = person(:organizer)

        assert wrapped.reload.organizer?(organizer), "the commitment's organizer still runs its checklist"
        assert Commitment.find(@commitments.first.id).organizer?(organizer)
        assert wrapped.organizer_candidate?(organizer)
        assert_equal :full, Checklists::Visibility.new(wrapped, organizer).prepare([ person(:member2).id ]).access(nil, person(:member2).id)
        assert_includes ChecklistPolicy::Scope.new(organizer.user, Checklist).resolve, wrapped
        assert ChecklistPolicy.new(organizer.user, wrapped).update?
        assert_not plain.organizer?(organizer), "a plain checklist follows checklists_organizers alone"
        assert_not plain.organizer_candidate?(organizer)
        assert_not wrapped.organizer?(person(:lapsed)), "the badge must still reach the team"
      end
    end
  end

  test "the checklist mirrors the commitment and its item counts the same" do
    commitment = @commitments.second
    checklist = Checklists::WrapCommitments.new.up.find { |made| made.title == commitment.title }
    item = checklist.checklist_items.sole

    assert_equal [ @club, Date.new(2026, 10, 1), Date.new(2026, 10, 31), "active", "self_and_leaders" ],
      [ checklist.team, checklist.starts_on, checklist.ends_on, checklist.status, checklist.read_level ]
    assert_equal [ person(:organizer).id ], checklist.checklist_organizers.pluck(:person_id), "lapsed no longer runs it, so isn't copied"
    assert_equal [ "count", commitment.id, true, "self_and_leaders" ], [ item.kind, item.commitment_id, item.wrapped?, item.read_level ]
    assert_equal({ "base_amount" => 2, "unit" => "shifts", "additional_amount" => 0, "counts_when" => "confirmed" }, item.config)
    assert_equal [ [ "include", "badge", @volunteer.id, @club.id ], [ "exclude", "badge", @rookie.id, nil ] ],
      checklist.population_rules.map { |rule| [ rule.effect, rule.target_type, rule.badge_id, rule.team_id ] }
    assert_empty item.checklist_rules

    stored = checklist.checklist_results.where(item_id: nil).pluck(:person_id)
    assert_equal Checklists.people_covered_by(checklist).ids.sort, stored.sort, "results are stored at once"

    progress = commitment.progress
    Checklists::Evaluator.new(checklist).call.each do |person_id, row|
      next assert(row[item.id].exempt?) unless progress[person_id]

      assert_equal progress[person_id].confirmed, row[item.id].measures["confirmed"]
    end
  end

  test "an owing badge under a lower owing team covers only the badge's holders in that team" do
    commitment = @commitments.third
    checklist = Checklists::WrapCommitments.new.up.find { |made| made.title == commitment.title }

    assert_equal [ [ "include", "badge", @volunteer.id, @members.id ] ], checklist.population_rules.map { |rule| [ rule.effect, rule.target_type, rule.badge_id, rule.team_id ] }
    assert_equal [ person(:kid).id, person(:member).id ].sort, Checklists.people_covered_by(checklist).ids.sort, "not crew_manager (Crew) nor member2 (no badge)"
    assert_not Checklists.meets?(checklist, person(:member2))
    assert_nil checklist.checklist_results.find_by(person: person(:member2))
  end

  test "wrapping twice wraps nothing new, and undoing it keeps every commitment" do
    wrapper = Checklists::WrapCommitments.new
    wrapper.up
    assert_no_difference -> { Checklist.count } do
      assert_empty wrapper.up
    end

    plain = Checklist.create!(team: @club, title: "Unrelated", created_by: person(:admin))
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

  def people
    @people.values.sort_by(&:id)
  end

  # The checklist covers exactly the people who owed the commitment, is
  # listed and opens for exactly the viewers the commitment was, and shows a
  # person's count, and their row, to exactly the viewers whose commitment
  # pages showed it (the snapshot's profile matrix), whether at full level or
  # not at all.
  def assert_checklist_shows_as_before(commitment, before)
    item = Commitment.find(commitment.id).checklist_item
    checklist = item.checklist
    covered = Checklists.people_covered_by(checklist).ids
    assert_equal before[:owing], covered.sort, "#{commitment.title}: the checklist covers who owed it"
    assert_equal before[:owing], Checklists::Population.applicable_ids(item, covered).sort, "#{commitment.title}: and the item applies to all of them"
    people.each_with_index do |viewer, v|
      message = "#{commitment.title}: listed to #{viewer.first_name}"
      assert_equal before[:listed][v], ChecklistPolicy::Scope.new(viewer.user, Checklist).resolve.exists?(id: checklist.id), message
      assert_equal before[:shown][v].first, ChecklistPolicy.new(viewer.user, checklist).show?, message
    end
    people.each_with_index do |viewer, v|
      visibility = Checklists::Visibility.new(checklist, viewer).prepare(covered)
      seen = Checklists.status_for(checklist, covered, viewer: viewer).keys
      people.each_with_index do |subject, s|
        next unless covered.include?(subject.id)

        expected = before[:profile][v][s]
        message = "#{commitment.title}: #{viewer.first_name} viewing #{subject.first_name}"
        [ item, nil ].each do |shown|
          expected ? assert_equal(:full, visibility.access(shown, subject.id), message) : assert_nil(visibility.access(shown, subject.id), message)
        end
        assert_equal expected, seen.include?(subject.id), message
      end
    end
  end

  def snapshot(commitment)
    commitment = Commitment.find(commitment.id)
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
