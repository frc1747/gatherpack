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

  test "the checklist's words are for the overall; items keep the defaults" do
    @checklist.update!(met_word: "Eligible", not_met_word: "Not eligible")
    item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    status = Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:admin))[person(:member).id]

    assert_equal "Not eligible", status.overall.text
    assert_equal "Not yet", status.item(item.id).text
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

  test "a badge rule with a team covers only holders in that team or below" do
    give_badge(:member, @safety)
    give_badge(:organizer, @safety)
    rule = add_rule(@checklist, :include, :badge, badge_id: @safety.id, team_id: @members.id)

    assert_equal [ person(:member) ], Checklists.people_covered_by(@checklist.reload).to_a
    assert_equal "Include Safety 2026 badge holders in Members", rule.description
    assert_equal @members.id, rule.reload.team_id, "kept for a badge rule"

    other_org_team = Team.create!(name: "Far", team_type: team_types(:one), parent: @other_org)
    outside = @checklist.checklist_rules.new(effect: :include, target_type: :badge, badge: @safety, team: other_org_team)
    assert_not outside.valid?
    assert_includes outside.errors[:base].join, "Must be within Club"
  end

  test "an item rule with a badge and team narrows to both" do
    item = add_item(@checklist, :has_login, "Login")
    give_badge(:member, @safety)
    give_badge(:organizer, @safety)
    add_rule(@checklist, :include, :badge, item: item, badge_id: @safety.id, team_id: @crew.id)

    assert_equal "met", evaluate(@checklist, :organizer, item).status
    assert_equal "exempt", evaluate(@checklist, :member, item).status
  end

  test "copying keeps a badge rule's team, and replaces it when asked" do
    next_crew = Team.create!(name: "Crew 2027", team_type: team_types(:one), parent: @club)
    old_crew = Team.create!(name: "Crew 2026", team_type: team_types(:one), parent: @club)
    add_rule(@checklist, :include, :badge, badge_id: @safety.id, team_id: old_crew.id)

    copy = Checklists::Copier.new(@checklist).call(title: "Copy", by: person(:admin))
    assert_equal old_crew.id, copy.population_rules.first.team_id
    moved = Checklists::Copier.new(@checklist).call(title: "Moved", by: person(:admin), replace: { "Team:#{old_crew.id}" => next_crew.id })
    assert_equal next_crew.id, moved.population_rules.first.team_id
    assert_equal @safety.id, moved.population_rules.first.badge_id
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

  # Review fixes

  test "a confirmation through another item counts only if this item's setting allows it" do
    manager_item = add_item(@checklist, :attested, "Physical", { statement: "Physical on file", attested_by: "manager" })
    other = create_world_checklist("Crew list", team: @members)
    self_item = add_item(other, :attested, "Physical", { statement: "Physical on file", attested_by: "person" })
    assert_equal manager_item.config["key"], self_item.config["key"], "same statement, same key"

    ChecklistAttestation.create!(person: person(:member), key: self_item.config["key"], statement: "Physical on file", attested_by: person(:member))
    assert_equal "met", evaluate(other, :member, self_item).status
    assert_equal "not_met", evaluate(@checklist, :member, manager_item).status, "a self-confirmation doesn't pass a manager-only item"

    ChecklistAttestation.create!(person: person(:member), key: manager_item.config["key"], statement: "Physical on file", attested_by: person(:club_manager))
    assert_equal "met", evaluate(@checklist, :member, manager_item).status
  end

  test "a guardian-confirmed item doesn't accept a stranger's confirmation" do
    item = add_item(@checklist, :attested, "Permission", { statement: "Permission given", attested_by: "guardian" })
    ChecklistAttestation.create!(person: person(:kid), key: item.config["key"], statement: "Permission given", attested_by: person(:member))
    assert_equal "not_met", evaluate(@checklist, :kid, item).status

    ChecklistAttestation.create!(person: person(:kid), key: item.config["key"], statement: "Permission given", attested_by: person(:parent))
    assert_equal "met", evaluate(@checklist, :kid, item).status
  end

  test "a group can't be moved inside a group it holds" do
    outer = add_item(@checklist, :any_of, "Outer")
    inner = add_item(@checklist, :any_of, "Inner", parent: outer)
    add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, parent: inner)

    outer.parent = inner
    assert_not outer.valid?
    assert_includes outer.errors[:parent], "can't be the item itself or a group inside it"
    assert_equal "not_met", evaluate(@checklist, :member).status
  end

  test "deleting a person named in an include rule leaves a rule that matches nobody" do
    add_rule(@checklist, :include, :person, person_id: person(:member).id)
    item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    add_rule(@checklist, :include, :person, item: item, person_id: person(:member).id)
    assert_equal [ person(:member) ], Checklists.people_covered_by(@checklist.reload).to_a

    person(:member).destroy!
    assert_empty Checklists.people_covered_by(@checklist.reload)
    assert_equal 2, @checklist.checklist_rules.where(person_id: nil).count
    assert_match "rule's person was deleted; it matches nobody", @checklist.problems.join

    other = create_world_checklist("Other")
    narrowed = add_item(other, :badge, "Safety", { badge_ids: [ @safety.id ] })
    add_rule(other, :include, :person, item: narrowed, person_id: person(:member2).id)
    person(:member2).destroy!
    assert_equal "exempt", evaluate(other, :kid, narrowed).status, "the item still applies to nobody else"
  end

  test "applicants to a team outside the checklist's reach aren't covered" do
    outside = Team.create!(name: "Elsewhere", team_type: team_types(:one), parent: @other_org, join_permission: :requires_approval)
    MembershipApplication.create!(person: person(:outsider), team: outside)
    rule = @checklist.checklist_rules.new(effect: :include, target_type: :applicants, team: outside)

    assert_not rule.valid?
    assert_not_includes Checklists::Population.new(@checklist, rules: [ rule ]).person_ids, person(:outsider).id
  end

  test "a cutoff or as-of date ignores badges, teams and logins added after it" do
    @checklist.update!(cutoff_on: Date.new(2026, 10, 1))
    badge = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    team = add_item(@checklist, :team_member, "Crew", { team_ids: [ @crew.id ] })
    login = add_item(@checklist, :has_login, "Login")
    travel_to(Time.zone.parse("2026-10-05")) do
      give_badge(:member, @safety)
      Membership.create!(person: person(:member), team: @crew)
    end

    travel_to(Time.zone.parse("2026-10-10")) do
      assert_equal "not_met", evaluate(@checklist, :member, badge).status
      assert_equal "not_met", evaluate(@checklist, :member, team).status
      assert_equal "not_met", evaluate(@checklist, :member, login).status, "the login was made after the cutoff"
    end
  end

  test "the clock refresh covers an excuse ending and an item's moving start" do
    item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    travel_to(Time.zone.parse("2026-11-10 10:00")) do
      ChecklistExcuse.create!(item: item, person: person(:member), reason: "Until the 20th", expires_on: Date.new(2026, 11, 20), created_by: person(:club_manager))
      assert_equal Time.zone.parse("2026-11-21 00:00"), Checklists::Evaluator.new(@checklist.reload).next_change_at

      item.update!(starts_within_amount: 30, starts_within_unit: "days")
      assert_equal Time.zone.parse("2026-11-11 00:00"), Checklists::Evaluator.new(@checklist.reload).next_change_at
    end
  end

  test "an organizer who loses their badge loses the full view" do
    with_settings(checklists_organizers: "Checklist Organizer > Club") do
      @checklist.checklist_organizers.create!(person: person(:organizer))
      assert Checklists::Visibility.new(@checklist, person(:organizer)).full?

      BadgeAssignment.find_by(person: person(:organizer), badge: @organizer_badge).destroy!
      assert_not @checklist.reload.organizer?(person(:organizer))
      assert_not Checklists::Visibility.new(@checklist, person(:organizer)).full?
      assert_not ChecklistPolicy.new(person(:organizer).user, @checklist).show?
    end
  end

  test "drafts show only to the people who run them" do
    @checklist.update!(status: :draft)
    add_item(@checklist, :has_login, "Login")
    refresh(@checklist)

    assert_empty Checklists.checklist_for(person(:member))
    assert_not ChecklistPolicy.new(person(:member).user, @checklist).show?
    assert_equal [ @checklist ], Checklists.checklist_for(person(:member), viewer: person(:admin)).map(&:first)
  end

  test "the overall's count of things to do counts only items the viewer sees" do
    login = add_item(@checklist, :has_login, "Login")
    add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    add_item(@checklist, :badge, "Viewer", { badge_ids: [ @viewer_badge.id ] })
    Person.find(person(:member).id).user.update_columns(email: "")
    @checklist.checklist_grants.create!(badge: @viewer_badge, item_ids: [ login.id ], access: :full)
    give_badge(:outsider, @viewer_badge)
    refresh(@checklist)

    overall = Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:outsider))[person(:member).id].overall
    assert_equal({ "unmet" => 1 }, overall.measures)
    assert_equal "1 to do", overall.summary
    assert_equal "3 to do", Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:admin))[person(:member).id].overall.summary
  end

  test "archived checklists are read-only, and can be restored" do
    @checklist.update!(status: :archived)
    policy = ChecklistPolicy.new(person(:admin).user, @checklist)

    assert_not policy.update?
    assert policy.restore?
    assert policy.copy?
    assert_not ChecklistItemPolicy.new(person(:admin).user, @checklist.checklist_items.new).create?
    assert_not ChecklistRulePolicy.new(person(:admin).user, @checklist.checklist_rules.new).create?
  end

  test "the change banner names the role of who changed it" do
    item = add_item(@checklist, :has_login, "Login")
    PaperTrail.request(whodunnit: person(:club_manager).user.id) { item.update!(label: "Sign-in") }
    assert_equal "Changed #{I18n.l(Date.current, format: :long)} by a manager: item Sign-in edited", @checklist.last_change_text

    PaperTrail.request(whodunnit: person(:admin).user.id) { item.destroy! }
    assert_match "by an admin: item Sign-in removed", @checklist.reload.last_change_text
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

    with_feature do
      assert_not @safety.destroy
      assert_match "Used by the checklist Trip", @safety.errors.full_messages.to_sentence
      assert_not @club.destroy
      assert Badge.exists?(@safety.id)
    end
  end

  test "with the feature off, deleting runs no checklist checks" do
    doomed = create_world_badge("Old 2025")
    add_item(@checklist, :badge, "Old", { badge_ids: [ doomed.id ] })

    queries = []
    counter = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("checklist") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { assert doomed.destroy }
    assert_empty queries
  end
end
