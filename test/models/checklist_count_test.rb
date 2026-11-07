require "test_helper"
require_relative "../support/checklists_count_world"

class ChecklistCountTest < ActiveSupport::TestCase
  include ChecklistsCountWorld
  include ActiveJob::TestHelper

  # Stands in for a source kind from another branch whose records change on a
  # notification (sign-ups).
  class NotifiedSource < Commitments::SourceKind
    def self.label = "Notified"
    def self.subject_type = "EventType"
    def self.subject_choices(_commitment, _person) = EventType.all
    def self.watches = [ "thing_changed.gatherpack" ]
    def records(_person_ids) = []
    def how_to_earn = Commitments::HowToEarn.new(text: "Be notified", links: [])
  end

  setup do
    build_commitments_world
    @checklist = create_count_checklist
  end

  test "a count item makes its commitment and edits it; the title stays as first set" do
    item = add_count_item(@checklist, "Shifts", { additional_amount: 1, counts_when: "planned" })
    commitment = item.commitment

    assert commitment.persisted?
    assert_equal [ "Shifts", @club, @club, "shifts", 2, 1 ], [ commitment.title, commitment.team, commitment.owing_team, commitment.unit, commitment.base_amount, commitment.additional_amount ]
    assert commitment.counts_planned?
    assert_equal [ Date.new(2026, 10, 1), Date.new(2026, 10, 31) ], [ commitment.starts_on, commitment.ends_on ]
    assert_equal "Doesn't owe", item.exempt_label

    item.update!(label: "Concessions", config_params: { base_amount: 3, unit: "hours" })
    commitment.reload
    assert_equal [ "Shifts", 3, "hours" ], [ commitment.title, commitment.base_amount, commitment.unit ]
    assert commitment.counts_confirmed?
  end

  test "a count needs an amount, a unit and a start date" do
    item = @checklist.checklist_items.new(kind: "count", label: "Shifts")
    item.config_params = { base_amount: 0 }
    assert_not item.valid?
    assert_includes item.errors[:base], "Say how many"
    assert_includes item.errors[:base], "Say what is counted, such as shifts"

    open = create_count_checklist("Open", starts_on: nil)
    item = open.checklist_items.new(kind: "count", label: "Shifts")
    item.config_params = { base_amount: 1, unit: "shifts" }
    assert_not item.valid?
    assert_includes item.errors[:base], "A count needs a start date, its own or the checklist's"
  end

  test "results equal the commitment engine's: capped, deduped, planned, confirmed and adjusted" do
    travel_to Time.zone.parse("2026-10-20 12:00")
    item = add_count_item(@checklist)
    twin = create_world_commitment
    [ item.commitment, twin ].each do |commitment|
      commitment.commitment_sources.create!(kind: "checkins", subject: @outreach, max_credits: 3)
      commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    end
    past = (1..4).map { |day| create_world_event("Outreach #{day}", "2026-10-#{day + 10} 10:00") }
    future = create_world_event("Later", "2026-10-25 10:00")
    past.each { |event| check_in(:member, event) }
    check_in(:member2, past.first)
    check_in(:member2, future)
    [ item.commitment, twin ].each { |commitment| commitment.commitment_adjustments.create!(person: person(:kid), credits: 2, reason: "Ran the raffle") }

    expected = { member: "met", member2: "pending", kid: "met" }
    expected.each do |name, status|
      result = count_result(@checklist, name, item)
      progress = twin.progress_for(person(name))
      assert_equal status, result.status, name.to_s
      assert_equal({ "confirmed" => progress.confirmed, "planned" => progress.planned, "owed" => progress.owed, "remaining" => progress.remaining }, result.measures)
      assert_equal "#{progress.counted} of 2 shifts", result.summary
    end
    assert_equal 3, count_result(@checklist, :member, item).measures["confirmed"], "the first source wins every event, up to its cap"

    with_checklists do
      linked = Commitment.find(item.commitment_id)
      expected.each_key { |name| assert_equal twin.progress_for(person(name)).confirmed, linked.progress_for(person(name)).confirmed }
    end
  end

  test "counting planned credit too finishes on what's planned" do
    travel_to Time.zone.parse("2026-10-20 12:00")
    item = add_count_item(@checklist, "Shifts", { counts_when: "planned" })
    item.commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    check_in(:member, create_world_event("Past", "2026-10-11 10:00"))
    check_in(:member, create_world_event("Later", "2026-10-25 10:00"))

    assert_equal "met", count_result(@checklist, :member, item).status
  end

  test "a pooled count is one number for the group, and relatives' records credit it" do
    travel_to Time.zone.parse("2026-11-15 12:00")
    item = add_count_item(@checklist, "Shifts", { group_relationship_type_id: @parent_of.id, additional_amount: 1 })
    twin = create_world_commitment(group_relationship_type: @parent_of, additional_amount: 1)
    [ item.commitment, twin ].each { |commitment| commitment.commitment_sources.create!(kind: "checkins", subject: @outreach) }
    Relationship.create!(parent: person(:organizer), child: person(:member2), relationship_type: @parent_of, created_by: person(:admin))
    events = (1..3).map { |day| create_world_event("Outreach #{day}", "2026-10-#{day + 10} 10:00") }
    check_in(:organizer, events[0])
    check_in(:organizer, events[1])
    check_in(:kid, events[2])

    kid = count_result(@checklist, :kid, item)
    sibling = count_result(@checklist, :member2, item)
    progress = twin.progress_for(person(:kid))
    assert_equal [ 3, 3 ], [ progress.owed, progress.confirmed ]
    assert_equal "met", kid.status
    assert_equal kid.summary, sibling.summary
    assert_equal "3 of 3 shifts", kid.summary
    assert_includes kid.detail, "Shared by a group of 2"
    assert_not_includes kid.detail, person(:member2).display_name
    assert_equal "not_met", count_result(@checklist, :member, item).status
  end

  test "who owes is the checklist's population narrowed by the item's rules" do
    holders = Badge.create!(name: "Volunteer", short: "V", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)
    BadgeAssignment.create!(badge: holders, person: person(:member))
    item = add_count_item(@checklist)
    @checklist.checklist_rules.create!(item: item, effect: :include, target_type: :badge, badge: holders)

    result = count_result(@checklist, :member2, item)
    assert result.exempt?
    assert_equal "Doesn't owe", result.label
    assert_equal "not_met", count_result(@checklist, :member, item).status

    with_checklists do
      assert_equal [ person(:member).id ], Commitment.find(item.commitment_id).owing_people.pluck(:id)
    end
    assert_equal @club.descendant_people.count, Commitment.find(item.commitment_id).owing_people.count, "with checklists off, its own columns"
  end

  test "a cutoff shortens the period" do
    travel_to Time.zone.parse("2026-11-15 12:00")
    @checklist.update!(cutoff_on: Date.new(2026, 10, 15))
    item = add_count_item(@checklist)
    item.commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    check_in(:member, create_world_event("Before", "2026-10-11 10:00"))
    check_in(:member, create_world_event("After", "2026-10-20 10:00"))

    assert_equal "1 of 2 shifts", count_result(@checklist, :member, item).summary
    with_checklists do
      assert_equal Date.new(2026, 10, 15).in_time_zone.end_of_day, Commitment.find(item.commitment_id).period_times.end
    end
  end

  test "relative dates resolve into the commitment's period at each refresh" do
    travel_to Time.zone.parse("2026-10-20 12:00")
    item = add_count_item(@checklist, "Shifts", {}, starts_within_amount: 1, starts_within_unit: "months")
    assert_equal Date.new(2026, 9, 20), item.commitment.reload.starts_on

    travel_to Time.zone.parse("2026-10-25 12:00")
    Checklists::Refresher.new(@checklist.reload).call
    assert_equal [ Date.new(2026, 9, 25), Date.new(2026, 10, 31) ], [ item.commitment.reload.starts_on, item.commitment.ends_on ]
    with_checklists do
      assert_equal Date.new(2026, 9, 25).in_time_zone.beginning_of_day, Commitment.find(item.commitment_id).period_times.begin
    end
  end

  test "a batch gives the same answers as one person at a time" do
    travel_to Time.zone.parse("2026-11-15 12:00")
    item = add_count_item(@checklist, "Shifts", { group_relationship_type_id: @parent_of.id })
    item.commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    check_in(:organizer, create_world_event("Outreach", "2026-10-11 10:00"))
    check_in(:member, create_world_event("Outreach 2", "2026-10-12 10:00"))
    names = %i[member member2 kid]

    batch = Checklists::Evaluator.new(@checklist.reload).call(names.map { |name| person(name).id })
    names.each do |name|
      single = count_result(@checklist, name, item)
      assert_equal [ single.status, single.summary, single.measures ], [ batch.dig(person(name).id, item.id).status, batch.dig(person(name).id, item.id).summary, batch.dig(person(name).id, item.id).measures ]
    end
  end

  test "a draft count item previews with no commitment row" do
    item = @checklist.checklist_items.new(kind: "count", label: "Shifts")
    item.config_params = { base_amount: 1, unit: "shifts" }
    item.id = SecureRandom.uuid

    preview = Checklists::Preview.new(@checklist, item: item)
    assert_equal 3, preview.counts["not_met"]
    assert_equal 0, Commitment.count
  end

  test "a copied checklist's count item gets a new commitment with the same sources and no adjustments" do
    item = add_count_item(@checklist)
    item.commitment.commitment_sources.create!(kind: "checkins", subject: @outreach, max_credits: 3)
    item.commitment.commitment_adjustments.create!(person: person(:member), credits: 1, reason: "Raffle")

    copy = Checklists::Copier.new(@checklist).call(title: "Next year", by: person(:admin))
    copied = copy.checklist_items.sole

    assert_not_equal item.commitment_id, copied.commitment_id
    assert_equal [ [ "checkins", @outreach.id, 3 ] ], copied.commitment.commitment_sources.map { |source| [ source.kind, source.subject_id, source.max_credits ] }
    assert_empty copied.commitment.commitment_adjustments
    assert_equal [ Date.new(2027, 10, 1), Date.new(2027, 10, 31) ], [ copied.commitment.starts_on, copied.commitment.ends_on ]
    assert_not copied.wrapped?
  end

  test "removing a count item removes its commitment, which can't be deleted on its own" do
    item = add_count_item(@checklist)
    commitment = Commitment.find(item.commitment_id)

    assert_not commitment.destroy
    assert commitment.errors[:base].any?

    item.reload.destroy!
    assert_not Commitment.exists?(commitment.id)
  end

  test "a linked commitment's organizers are the checklist's, read through checklists_organizers then commitments_organizers" do
    item = add_count_item(@checklist)
    commitment = Commitment.find(item.commitment_id)
    @checklist.checklist_organizers.new(person: person(:organizer)).save!(validate: false)
    other = Badge.create!(name: "Other Organizer", short: "OO", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)

    with_checklists(feature_badges: "true", commitments_organizers: "Commitment Organizer > Club") do
      assert commitment.organizer?(person(:organizer))
      assert commitment.organizer?(person(:crew_manager)) == @checklist.organizer?(person(:crew_manager))
      assert_not commitment.organizer?(person(:member))
    end
    with_checklists(feature_badges: "true", commitments_organizers: "Commitment Organizer > Club", checklists_organizers: "#{other.name} > Club") do
      assert_not commitment.organizer?(person(:organizer))
    end
  end

  test "checklists on treats commitments as on, without showing its menu item" do
    with_settings(feature_checklists: "false", feature_commitments: "false") do
      assert_not GatherPack::Features.enabled?(:commitments)
    end
    with_settings(feature_checklists: "true", feature_commitments: "false") do
      assert GatherPack::Features.enabled?(:commitments)
      labels = GatherPack::Features.nav_sections.flat_map { |_, items| items.map(&:label) }
      assert_includes labels, "Checklists"
      assert_not_includes labels, "Commitments"
    end
  end

  test "a pooled count is seen by a parent in the group; an unpooled one only once set to family" do
    @parent_of.update!(guardianship: :minor)
    person(:kid).update!(birthday: Date.new(2014, 3, 1))
    pooled = add_count_item(@checklist, "Pooled", { group_relationship_type_id: @parent_of.id })
    alone = add_count_item(@checklist, "Alone")
    parent = person(:organizer)
    visibility = Checklists::Visibility.new(@checklist.reload, parent).prepare([ person(:kid).id, person(:member).id ])

    assert_equal "group", pooled.effective_read_level
    assert_equal "self_and_leaders", alone.effective_read_level
    assert_equal :full, visibility.access(pooled, person(:kid).id)
    assert_nil visibility.access(pooled, person(:member).id)
    assert_nil visibility.access(alone, person(:kid).id)

    alone.update!(read_level: "family")
    visibility = Checklists::Visibility.new(@checklist.reload, parent).prepare([ person(:kid).id ])
    assert_equal :full, visibility.access(@checklist.checklist_items.find(alone.id), person(:kid).id)
  end

  test "a check-in, and a source's watched notification, mark count checklists" do
    Commitments.register_source(:notified, NotifiedSource)
    add_count_item(@checklist)
    with_checklists do
      ChecklistRefresh.delete_all
      check_in(:member, create_world_event("Outreach", "2026-10-11 10:00"))
      assert ChecklistRefresh.exists?(checklist: @checklist, person_id: nil)

      ChecklistRefresh.delete_all
      ActiveSupport::Notifications.instrument("thing_changed.gatherpack")
      assert ChecklistRefresh.exists?(checklist: @checklist, person_id: nil)

      ChecklistRefresh.delete_all
      ActiveSupport::Notifications.instrument("unwatched.gatherpack")
      assert_empty ChecklistRefresh.all
    end
  ensure
    Commitments.unregister_source(:notified)
  end

  test "organizers see a count with nothing counting toward it as a problem" do
    item = add_count_item(@checklist)
    assert_includes @checklist.reload.problems, "Shifts: Nothing counts toward it yet"

    item.commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    assert_empty @checklist.reload.problems
  end
end
