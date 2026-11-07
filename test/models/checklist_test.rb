require "test_helper"
require_relative "../support/checklists_world"

class ChecklistTest < ActiveSupport::TestCase
  include ChecklistsWorld

  setup do
    build_checklists_world
    @checklist = create_world_checklist
  end

  # Overall and combining

  test "overall: any counting item not met, else any pending, else done; exempt and non-counting ignored" do
    login = add_item(@checklist, :has_login, "Login")
    safety = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, counts: false)

    assert_equal "met", evaluate(@checklist, :member).status, "Safety doesn't count"
    safety.update!(counts: true)
    assert_equal "not_met", evaluate(@checklist, :member).status

    add_rule(@checklist, :exclude, :person, item: safety, person_id: person(:member).id)
    safety.update!(exempt_label: "Rookie")
    assert_equal "Rookie", evaluate(@checklist, :member, safety).label
    assert_equal "met", evaluate(@checklist, :member).status
    assert login
  end

  test "a checklist with no items is done for everyone it covers" do
    assert_equal "met", evaluate(@checklist, :member).status
  end

  test "any_of: one child is enough, groups nest to any depth" do
    group = add_item(@checklist, :any_of, "Safety or login")
    add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, parent: group)
    inner = add_item(@checklist, :any_of, "Inner", parent: group)
    deep = add_item(@checklist, :badge, "Viewer", { badge_ids: [ @viewer_badge.id ] }, parent: inner)

    assert_equal "not_met", evaluate(@checklist, :member, group).status
    give_badge(:member, @viewer_badge)
    result = evaluate(@checklist, :member, group)
    assert_equal "met", result.status
    assert_equal "Inner done", result.summary
    assert_equal "met", evaluate(@checklist, :member, deep).status, "children are stored too"
    assert_equal "met", evaluate(@checklist, :member).status
  end

  test "any_of: pending when no child is met but one is pending" do
    group = add_item(@checklist, :any_of, "Either")
    other = create_world_checklist("Other")
    add_item(other, :has_login, "Login")
    refresh(other)
    ChecklistResult.where(checklist: other, person: person(:member), item_id: nil).update_all(status: ChecklistResult.statuses[:pending])
    add_item(@checklist, :checklist, "Other", { checklist_id: other.id }, parent: group)
    add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, parent: group)

    assert_equal "pending", evaluate(@checklist, :member, group).status
    assert_equal "pending", evaluate(@checklist, :member).status
  end

  test "an item's parent must be a group on the same checklist" do
    login = add_item(@checklist, :has_login, "Login")
    item = @checklist.checklist_items.new(kind: "has_login", label: "Nested", parent: login)

    assert_not item.valid?
    assert_includes item.errors[:parent], "must be a group on the same checklist"
  end

  test "cycles are refused, directly or through others" do
    other = create_world_checklist("Other")
    third = create_world_checklist("Third")
    add_item(other, :checklist, "Third", { checklist_id: third.id })
    add_item(third, :checklist, "Trip", { checklist_id: @checklist.id })

    itself = @checklist.checklist_items.new(kind: "checklist", label: "Self", config: { "checklist_id" => @checklist.id })
    assert_not itself.valid?
    assert_includes itself.errors[:base], "A checklist can't require itself"

    loop_item = @checklist.checklist_items.new(kind: "checklist", label: "Other", config: { "checklist_id" => other.id })
    assert_not loop_item.valid?
    assert_includes loop_item.errors[:base].join, "already requires this one"
  end

  test "a long chain of checklists without a loop is allowed" do
    previous = @checklist
    5.times do |index|
      nested = create_world_checklist("Level #{index}")
      add_item(previous, :checklist, nested.title, { checklist_id: nested.id })
      previous = nested
    end

    assert_equal 6, ChecklistItem.reachable_checklist_ids([ @checklist.id ]).size
  end

  # Population

  test "covers its team and below by default, and rules include or exclude" do
    covered = Checklists.people_covered_by(@checklist)
    assert_includes covered, person(:member)
    assert_includes covered, person(:crew_manager)
    assert_not_includes covered, person(:outsider)
    assert_not_includes covered, person(:applicant), "applicants only through an applicants rule"

    add_rule(@checklist, :include, :team, team_id: @members.id)
    add_rule(@checklist, :exclude, :person, person_id: person(:rookie).id)
    covered = Checklists.people_covered_by(@checklist.reload)
    assert_equal %w[Kid Member MemberTwo].sort, covered.map(&:first_name).sort
  end

  test "an include team rule can leave managers out" do
    add_rule(@checklist, :include, :team, team_id: @crew.id, include_managers: false)

    assert_equal [ person(:organizer) ], Checklists.people_covered_by(@checklist.reload).to_a
  end

  test "applicants are covered through their application, and leave when it's decided" do
    add_rule(@checklist, :include, :applicants, team_id: @joiners.id)
    assert_includes Checklists.people_covered_by(@checklist.reload), person(:applicant)

    MembershipApplication.find_by(person: person(:applicant)).deny!
    assert_not_includes Checklists.people_covered_by(@checklist.reload), person(:applicant)
  end

  test "rules must stay within the checklist's team" do
    rule = @checklist.checklist_rules.new(effect: :include, target_type: :team, team: @other_org)

    assert_not rule.valid?
    assert_includes rule.errors[:base].join, "Must be within Club"
  end

  test "a badge's holders outside the team aren't covered" do
    add_rule(@checklist, :include, :badge, badge_id: @safety.id)
    give_badge(:outsider, @safety)
    give_badge(:member, @safety)

    assert_equal [ person(:member) ], Checklists.people_covered_by(@checklist.reload).to_a
  end

  # Excuses

  test "an excuse takes the item off the person and says who and when" do
    item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    ChecklistExcuse.create!(item: item, person: person(:member), reason: "Injured", created_by: person(:club_manager))

    result = evaluate(@checklist, :member, item)
    assert_equal "exempt", result.status
    assert_equal "Excused", result.label
    assert_equal "ClubManager World", result.excuse["by"]
    assert_equal "met", evaluate(@checklist, :member).status
  end

  test "an expired excuse no longer applies" do
    item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    ChecklistExcuse.create!(item: item, person: person(:member), reason: "Until spring", expires_on: Date.new(2026, 12, 31), created_by: person(:club_manager))

    travel_to(Time.zone.parse("2026-12-31 12:00")) { assert_equal "exempt", evaluate(@checklist, :member, item).status }
    travel_to(Time.zone.parse("2027-01-01 12:00")) { assert_equal "not_met", evaluate(@checklist, :member, item).status }
  end

  test "only managers of the checklist's team and above, and admins, excuse; never themselves or a relative" do
    item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    excuse = ->(by, who) { ChecklistExcuse.new(item: item, person: person(who), reason: "Because", created_by: person(by)) }

    assert excuse.call(:club_manager, :member).valid?
    assert excuse.call(:admin, :member).valid?
    assert_not excuse.call(:crew_manager, :member).valid?, "manages a team below the checklist's"
    assert_not excuse.call(:organizer, :member).valid?, "organizers don't excuse"
    assert_includes excuse.call(:club_manager, :club_manager).tap(&:valid?).errors[:base], ChecklistExcuse::SELF_REASON

    Membership.create!(person: person(:parent), team: @club, manager: true)
    assert_includes excuse.call(:parent, :kid).tap(&:valid?).errors[:base], ChecklistExcuse::SELF_REASON
  end

  test "excuses are audited" do
    item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })

    assert_difference -> { AuditLog.where(item_type: "ChecklistExcuse").count }, 1 do
      ChecklistExcuse.create!(item: item, person: person(:member), reason: "Injured", created_by: person(:club_manager))
    end
  end

  # Grants and organizers

  test "only admin-assigned badges can grant" do
    assert ChecklistGrant.new(checklist: @checklist, badge: @viewer_badge).valid?
    grant = ChecklistGrant.new(checklist: @checklist, badge: @helper_badge)

    assert_not grant.valid?
    assert_includes grant.errors[:badge], "must be one only admins give"
  end

  test "organizers need a granting badge that reaches the team" do
    with_settings(checklists_organizers: "Checklist Organizer > Club") do
      assert @checklist.checklist_organizers.create(person: person(:organizer)).persisted?
      assert @checklist.organizer?(person(:organizer))
      assert_not @checklist.checklist_organizers.create(person: person(:member)).persisted?
    end
  end

  # Predicates

  test "people_meeting is a relation, strict by default" do
    add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    give_badge(:member, @safety)
    refresh(@checklist)
    ChecklistResult.where(checklist: @checklist, person: person(:member2), item_id: nil).update_all(status: ChecklistResult.statuses[:pending])

    relation = Checklists.people_meeting(@checklist)
    assert_kind_of ActiveRecord::Relation, relation
    assert_equal [ person(:member) ], relation.to_a
    assert_equal [ person(:member) ], relation.where(first_name: "Member").to_a
    assert_equal %w[Member MemberTwo], Checklists.people_meeting(@checklist, accept: %i[met pending]).map(&:first_name).sort
    assert Checklists.meets?(@checklist, person(:member))
    assert_not Checklists.meets?(@checklist, person(:member2))
  end

  test "the team and rule targets can't be deleted while used" do
    add_rule(@checklist, :include, :badge, badge_id: @safety.id)

    assert_not @safety.destroy
    assert_not @club.destroy
    assert Badge.exists?(@safety.id)
  end
end
