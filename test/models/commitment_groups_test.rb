require "test_helper"
require_relative "../support/commitments_world"

# Groups (spec §4.4), the exempt badge, planned check-ins and the progress
# API reports read.
class CommitmentGroupsTest < ActiveSupport::TestCase
  include CommitmentsWorld

  setup do
    travel_to Time.zone.parse("2026-11-15 12:00")
    build_commitments_world
    @parent_a = create_world_person("ParentA")
    @parent_b = create_world_person("ParentB")
    @commitment = create_world_commitment(group_relationship_type: @parent_of, base_amount: 2, additional_amount: 1)
    @games = (1..4).map { |day| create_world_event("Outreach #{day}", "2026-10-#{day + 10} 10:00") }
  end

  test "people connected directly through the relationship type are one group" do
    sibling_of = RelationshipType.create!(parent_label: "Sibling of", child_label: "Sibling of", permission: :added_by_admin)
    relate(person(:member), person(:member2), sibling_of)
    @commitment.update!(group_relationship_type: sibling_of)

    assert_equal names(:member, :member2), @commitment.group_for(person(:member)).map(&:first_name)
    assert_equal names(:kid), @commitment.group_for(person(:kid)).map(&:first_name), "the Parent of link doesn't count for this type"
  end

  test "a chain through people who don't owe makes one group: half-siblings" do
    relate(@parent_a, person(:member))
    relate(@parent_a, person(:kid))
    relate(@parent_b, person(:kid))
    relate(@parent_b, person(:member2))

    group = @commitment.group_for(person(:member2))
    assert_equal names(:kid, :member, :member2), group.map(&:first_name)
    assert_equal group, @commitment.group_for(person(:member))
    assert_equal 1, @commitment.progress.values.uniq.size
  end

  test "two people who don't owe never link groups: a grandparent doesn't make cousins one group" do
    grandparent = create_world_person("Grandparent")
    relate(grandparent, @parent_a)
    relate(grandparent, @parent_b)
    relate(@parent_a, person(:member))
    relate(@parent_a, person(:kid))
    relate(@parent_b, person(:member2))

    assert_equal names(:kid, :member), @commitment.group_for(person(:member)).map(&:first_name)
    assert_equal names(:member2), @commitment.group_for(person(:member2)).map(&:first_name)
    assert_equal 2, @commitment.progress.values.uniq.size
    assert_equal names(:kid, :member), @commitment.progress_seen_by(@parent_a).members.map(&:first_name)
    assert_nil @commitment.progress_seen_by(grandparent), "related to no owing person directly"
  end

  test "someone with no connection is a group of one, and so is everyone when the commitment isn't grouped" do
    relate(@parent_a, person(:member))
    relate(@parent_a, person(:kid))

    assert_equal names(:member2), @commitment.group_for(person(:member2)).map(&:first_name)
    assert_equal 2, @commitment.progress.values.uniq.size
    assert_empty @commitment.group_for(person(:outsider))

    @commitment.update!(group_relationship_type: nil)
    assert_equal [ person(:member) ], @commitment.group_for(person(:member))
    assert_equal 3, @commitment.progress.values.uniq.size
  end

  test "a group owes base plus additional for each member after the first" do
    relate(@parent_a, person(:member))
    relate(@parent_a, person(:kid))
    relate(@parent_a, person(:member2))
    @commitment.update!(base_amount: 2, additional_amount: 1)
    assert_equal 4, @commitment.progress_for(person(:kid)).owed

    @commitment.update!(base_amount: 3, additional_amount: 0)
    assert_equal 3, @commitment.progress_for(person(:kid)).owed

    @commitment.update!(group_relationship_type: nil, additional_amount: 5)
    assert_equal 3, @commitment.progress_for(person(:kid)).owed, "a group of one owes the base"
  end

  test "members' credit pools, caps apply per group, and dedupe stays per person" do
    relate(@parent_a, person(:member))
    relate(@parent_a, person(:kid))
    @commitment.update!(base_amount: 4, additional_amount: 1)
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach, max_credits: 3)
    check_in(:member, @games[0])
    check_in(:kid, @games[0])
    check_in(:kid, @games[1])
    @commitment.commitment_adjustments.create!(person: person(:member), credits: 1, reason: "Ran the raffle")

    everyone = @commitment.progress
    assert_same everyone[person(:member).id], everyone[person(:kid).id], "members share their group's progress"
    progress = @commitment.progress_for(person(:member))
    assert_equal 5, progress.owed
    assert_equal 3, progress.lines.first.records.size, "two siblings at one event are two records"
    assert_equal 4, progress.confirmed
    assert_equal 1, progress.remaining

    check_in(:kid, @games[2])
    check_in(:member, @games[3])
    progress = @commitment.progress_for(person(:member))
    line = progress.lines.first
    assert_equal 5, line.records.size
    assert_equal 3, line.confirmed_credits, "the cap is the group's, not each member's"
    assert line.capped
    assert_equal 4, progress.confirmed
    assert_not progress.met?
  end

  test "holders of the exempt badge don't owe, can't be adjusted, and organizers don't see them" do
    rookie = Badge.create!(name: "Rookie", short: "R", color: "#00aa00", badge_type: badge_types(:one), permission: :added_by_admin)
    BadgeAssignment.create!(badge: rookie, person: person(:member2))
    @commitment.update!(exempt_badge: rookie)

    assert_not @commitment.covers?(person(:member2))
    assert_not_includes @commitment.owing_people, person(:member2)
    assert_nil @commitment.progress_for(person(:member2))
    assert_not_includes @commitment.progress.keys, person(:member2).id
    assert_not @commitment.commitment_adjustments.build(person: person(:member2), credits: 1, reason: "x").valid?

    with_organizer_grants("Commitment Organizer > Club") do
      @commitment.commitment_organizers.create!(person: person(:organizer))
      assert PersonCommitmentsPolicy.new(person(:organizer).user, person(:member)).show?
      assert_not PersonCommitmentsPolicy.new(person(:organizer).user, person(:member2)).show?
      assert_not CommitmentPolicy.new(person(:member2).user, @commitment).show?
    end

    @commitment.owing_badge = rookie
    assert_not @commitment.valid?
    assert @commitment.errors[:exempt_badge_id].any?
  end

  # Once exempt, the kid doesn't owe, so parent_a -> kid -> parent_b links
  # people who don't owe and joins nothing; owing half-siblings still do.
  test "an exempt person neither joins a group nor links the families on either side" do
    rookie = Badge.create!(name: "Rookie", short: "R", color: "#00aa00", badge_type: badge_types(:one), permission: :added_by_admin)
    BadgeAssignment.create!(badge: rookie, person: person(:kid))
    relate(@parent_a, person(:member))
    relate(@parent_a, person(:kid))
    relate(@parent_b, person(:kid))
    relate(@parent_b, person(:member2))
    assert_equal names(:kid, :member, :member2), @commitment.group_for(person(:member)).map(&:first_name), "while the kid owes"

    @commitment.update!(exempt_badge: rookie)
    assert_equal names(:member), @commitment.group_for(person(:member)).map(&:first_name)
    assert_equal names(:member2), @commitment.group_for(person(:member2)).map(&:first_name)
    assert_empty @commitment.group_for(person(:kid))
  end

  test "the exempt badge and the group relationship type can't be deleted out from under a commitment" do
    rookie = Badge.create!(name: "Rookie", short: "R", color: "#00aa00", badge_type: badge_types(:one), permission: :added_by_admin)
    @commitment.update!(exempt_badge: rookie)

    assert_not rookie.destroy
    assert_equal [ "Cannot delete record because dependent exempting commitments exist" ], rookie.errors.full_messages
    assert_not @parent_of.destroy
    assert_includes @parent_of.errors.full_messages, "Cannot delete record because dependent grouping commitments exist"
    assert_equal [ rookie, @parent_of ], [ @commitment.reload.exempt_badge, @commitment.group_relationship_type ]
  end

  test "a check-in at an event that hasn't started is planned, and confirmed once it has" do
    travel_back
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    travel_to Time.zone.parse("2026-10-11 09:00") do
      check_in(:member, @games[0])
      check_in(:member, @games[1])

      progress = @commitment.progress_for(person(:member))
      assert_equal [ 0, 2 ], [ progress.confirmed, progress.planned ]
      assert_equal [ false, false ], progress.lines.first.records.map(&:confirmed?)
    end
    travel_to Time.zone.parse("2026-10-11 10:00") do
      progress = @commitment.progress_for(person(:member))
      assert_equal [ 1, 1 ], [ progress.confirmed, progress.planned ], "the first event has started"
    end
    travel_to Time.zone.parse("2026-10-13 12:00") do
      progress = @commitment.progress_for(person(:member))
      assert_equal [ 2, 0 ], [ progress.confirmed, progress.planned ]
      assert progress.met?
    end
  end

  test "a parent sees their children's group, read-only, and nobody else's" do
    relate(@parent_a, person(:member))
    relate(@parent_a, person(:kid))
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    check_in(:kid, @games[0])

    assert @commitment.group_relative?(@parent_a)
    assert_not @commitment.covers?(@parent_a)
    progress = @commitment.progress_seen_by(@parent_a)
    assert_equal names(:kid, :member), progress.members.map(&:first_name)
    assert_equal 1, progress.confirmed
    assert_nil @commitment.progress_seen_by(@parent_b)

    parent_policy = CommitmentPolicy.new(@parent_a.user, @commitment)
    assert parent_policy.show?
    assert_not parent_policy.progress?
    assert_not parent_policy.manage?
    assert_equal [ @commitment ], CommitmentPolicy::Scope.new(@parent_a.user, Commitment).resolve.to_a

    assert_equal [ @commitment ], PersonCommitmentsPolicy.new(@parent_a.user, @parent_a).visible_commitments
    assert_equal [ @commitment ], PersonCommitmentsPolicy.new(@parent_a.user, person(:member)).visible_commitments
    assert_not PersonCommitmentsPolicy.new(@parent_a.user, person(:member2)).show?

    @commitment.update!(group_relationship_type: nil)
    assert_not @commitment.group_relative?(@parent_a)
    assert_not CommitmentPolicy.new(@parent_a.user, @commitment).show?
    assert_not PersonCommitmentsPolicy.new(@parent_a.user, person(:member)).show?
  end

  test "nobody adjusts credit for anyone in a group with themselves or a relative" do
    relate(@parent_b, person(:kid))
    relate(@parent_b, person(:member2))
    with_organizer_grants("Commitment Organizer > Club") do
      @commitment.commitment_organizers.create!(person: person(:organizer))
      policy = ->(name) { CommitmentAdjustmentPolicy.new(person(:organizer).user, CommitmentAdjustment.new(commitment: @commitment, person: person(name))) }

      assert_not policy.(:kid).create?
      assert_not policy.(:member2).create?, "in a group with the organizer's child"
      assert_equal Commitment::SELF_APPROVAL_REASON, policy.(:member2).self_approval_reason
      assert policy.(:member).create?
    end
  end

  test "the report API: covers?, progress_for and a batch progress for many people in a fixed number of queries" do
    relate(@parent_a, person(:member))
    relate(@parent_a, person(:kid))
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach, max_credits: 1)
    @commitment.commitment_sources.create!(kind: "checkins", subject: @meeting)
    check_in(:member, @games[0])
    check_in(:kid, create_world_event("Meeting", "2026-10-20 18:00", event_type: @meeting))

    assert @commitment.covers?(person(:member))
    assert_not @commitment.covers?(@parent_a)
    progress = @commitment.progress_for(person(:kid))
    assert_equal [ 3, 2, 0, 1, false ], [ progress.owed, progress.confirmed, progress.planned, progress.remaining, progress.met? ]
    assert_equal names(:kid, :member), progress.members.map(&:first_name)
    assert_equal [ [ "Check-ins: Outreach", 1 ], [ "Check-ins: Meeting", 1 ] ], progress.lines.map { |line| [ line.source.label, line.confirmed_credits ] }
    assert_nil @commitment.progress_for(person(:outsider))
    assert_equal [ person(:member).id ], @commitment.progress([ person(:member), person(:outsider) ]).keys

    few = queries { Commitment.find(@commitment.id).progress(@commitment.owing_people.to_a) }
    20.times do |i|
      someone = create_world_person("Extra#{i}", @members)
      relate(@parent_b, someone) if i.even?
      Checkin.create!(person: someone, event: @games[i % 4])
    end
    many = queries { Commitment.find(@commitment.id).progress(@commitment.owing_people.to_a) }
    assert_equal 23, @commitment.owing_people.count
    assert_equal few, many, "the batch doesn't query per person"
  end

  private

  def relate(parent, child, type = @parent_of)
    Relationship.create!(parent: parent, child: child, relationship_type: type, created_by: person(:admin))
  end

  def names(*keys)
    keys.map { |key| person(key).first_name }
  end

  def queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveRecord::Base.uncached { ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block) }
    count
  end
end
