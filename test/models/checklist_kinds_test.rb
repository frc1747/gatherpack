require "test_helper"
require_relative "../support/checklists_world"

class ChecklistKindsTest < ActiveSupport::TestCase
  include ChecklistsWorld

  setup do
    build_checklists_world
    @checklist = create_world_checklist
  end

  test "every core kind gives the same answer in a batch as for one person" do
    give_badge(:member, @safety)
    ChecklistAttestation.create!(person: person(:member2), key: "handbook", statement: "Handbook read", attested_by: person(:member2), attested_at: Time.zone.parse("2026-10-01"))
    other = create_world_checklist("Other")
    add_item(other, :has_login, "Login")
    items = [
      add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }),
      add_item(@checklist, :team_member, "Crew", { team_ids: [ @crew.id ] }),
      add_item(@checklist, :has_login, "Login"),
      add_item(@checklist, :age, "Age", { min: 12 }),
      add_item(@checklist, :attested, "Handbook", { statement: "Handbook read", key: "handbook" }),
      add_item(@checklist, :checklist, "Other", { checklist_id: other.id })
    ]
    refresh(other)
    names = %i[member member2 kid rookie organizer]

    travel_to Time.zone.parse("2026-11-01 12:00") do
      batch = Checklists::Evaluator.new(@checklist.reload).call(names.map { |name| person(name).id })
      names.each do |name|
        single = Checklists::Evaluator.new(@checklist.reload).call([ person(name).id ])[person(name).id]
        items.each do |item|
          assert_equal single[item.id].status, batch.dig(person(name).id, item.id).status, "#{item.label} for #{name}"
          assert_equal single[item.id].summary, batch.dig(person(name).id, item.id).summary
        end
        assert_equal single[nil].status, batch.dig(person(name).id, nil).status
      end
    end
  end

  test "every core kind's fix says who acts on it, and any_of passes up its child's" do
    other = create_world_checklist("Other")
    add_item(other, :badge, "Safety", { badge_ids: [ @safety.id ] })
    refresh(other)
    expected = {
      add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }) => "leader",
      add_item(@checklist, :team_member, "Crew", { team_ids: [ @crew.id ] }) => "leader",
      add_item(@checklist, :age, "Age", { min: 12 }) => "person",
      add_item(@checklist, :attested, "Own", { statement: "Own", attested_by: "person" }) => "person",
      add_item(@checklist, :attested, "Guardian", { statement: "Guardian", attested_by: "guardian" }) => "guardian",
      add_item(@checklist, :attested, "Leader", { statement: "Leader", attested_by: "manager" }) => "leader",
      add_item(@checklist, :checklist, "Other", { checklist_id: other.id }) => "leader"
    }
    either = add_item(@checklist, :any_of, "Either")
    add_item(@checklist, :badge, "Badge first", { badge_ids: [ @safety.id ] }, parent: either)
    add_item(@checklist, :attested, "Then confirm", { statement: "Then confirm", attested_by: "guardian" }, parent: either)
    expected[add_item(@checklist, :has_login, "Login")] = "leader"
    nobody = Person.create!(first_name: "No", last_name: "Login")
    Membership.create!(person: nobody, team: @members)

    results = Checklists::Evaluator.new(@checklist.reload).call([ nobody.id ])[nobody.id]

    expected.each { |item, by| assert_equal by, results[item.id].fix["by"], item.label }
    confirm = @checklist.checklist_items.find_by!(label: "Then confirm")
    assert_equal({ "label" => "I confirm", "action" => "attest", "key" => "then-confirm", "by" => "guardian", "item_id" => confirm.id },
      results[either.id].fix, "one the person can do beats a leader's, though listed second")
  end

  test "any_of passes up the first child's fix when only a leader can act on any of them" do
    either = add_item(@checklist, :any_of, "Either")
    first = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, parent: either)
    add_item(@checklist, :attested, "Leader", { statement: "Leader", attested_by: "manager" }, parent: either)

    fix = evaluate(@checklist, :member, either).fix

    assert_equal({ "label" => "Ask a leader", "by" => "leader", "item_id" => first.id }, fix)
  end

  test "badge: holds any of the badges, optionally given within the dates" do
    item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id, @viewer_badge.id ] })
    travel_to(Time.zone.parse("2026-08-01")) { give_badge(:member, @safety) }

    assert_equal "met", evaluate(@checklist, :member, item).status
    assert_equal "not_met", evaluate(@checklist, :member2, item).status

    item.update!(config: item.config.merge("within_dates" => true))
    assert_equal "not_met", evaluate(@checklist, :member, item).status, "given before the window"
  end

  test "badge: a deleted badge is a problem and passes nobody" do
    doomed = create_world_badge("Old 2025")
    item = add_item(@checklist, :badge, "Old", { badge_ids: [ doomed.id ] })

    with_feature do
      assert_not doomed.destroy, "the item protects the badge"
      assert_match "Used by the checklist Trip", doomed.errors.full_messages.to_sentence
    end

    item.update_columns(config: { "badge_ids" => [ SecureRandom.uuid ] })
    assert_includes @checklist.reload.problems.join, "was deleted"
    assert_equal "not_met", evaluate(@checklist, :member, item).status
  end

  test "team_member: a team or one below it" do
    club = add_item(@checklist, :team_member, "On Club", { team_ids: [ @club.id ] })
    crew = add_item(@checklist, :team_member, "On Crew", { team_ids: [ @crew.id ] })

    assert_equal "met", evaluate(@checklist, :member, club).status
    assert_equal "met", evaluate(@checklist, :organizer, crew).status
    assert_equal "not_met", evaluate(@checklist, :member, crew).status
  end

  test "has_login: needs a user with an email" do
    item = add_item(@checklist, :has_login, "Login")
    nobody = Person.create!(first_name: "No", last_name: "Login")
    Membership.create!(person: nobody, team: @members)

    assert_equal "met", evaluate(@checklist, :member, item).status
    result = Checklists::Evaluator.new(@checklist.reload).call([ nobody.id ]).dig(nobody.id, item.id)
    assert_equal "not_met", result.status
    assert_equal "Ask a leader to invite you", result.fix["label"]
  end

  test "age: on the window's end, and no birthday is not yet with the reason" do
    @checklist.update!(ends_on: Date.new(2027, 6, 30))
    item = add_item(@checklist, :age, "Under 14", { max: 13 })

    assert_equal "met", evaluate(@checklist, :kid, item).status, "13 on 2027-06-30"
    missing = evaluate(@checklist, :member, item)
    assert_equal "not_met", missing.status
    assert_equal "No birthday on file", missing.summary
    assert_no_match "2014", evaluate(@checklist, :kid, item).detail.to_s
  end

  test "age: measured today when the window runs to now, and changes at midnight" do
    @checklist.update!(ends_on: nil)
    item = add_item(@checklist, :age, "Twelve or older", { min: 12 })

    travel_to(Time.zone.parse("2026-02-28 18:00")) do
      assert_equal "not_met", evaluate(@checklist, :kid, item).status
      assert_equal Time.zone.parse("2026-03-01 00:00"), Checklists::Evaluator.new(@checklist.reload).next_change_at
    end
    travel_to(Time.zone.parse("2026-03-01 08:00")) do
      assert_equal "met", evaluate(@checklist, :kid, item).status
    end
  end

  test "attested: counts confirmations within the item's dates, by key" do
    item = add_item(@checklist, :attested, "Physical", { statement: "Physical on file", attested_by: "guardian" }, starts_within_amount: 12, starts_within_unit: "months")
    ChecklistAttestation.create!(person: person(:kid), key: item.config["key"], statement: "Physical on file", attested_by: person(:parent), attested_at: Time.zone.parse("2026-01-10"))

    travel_to(Time.zone.parse("2026-12-01")) { assert_equal "met", evaluate(@checklist, :kid, item).status }
    travel_to(Time.zone.parse("2027-02-01")) do
      result = evaluate(@checklist, :kid, item)
      assert_equal "not_met", result.status, "more than 12 months ago"
      assert_equal "attest", result.fix["action"]
    end
  end

  test "attested: who may confirm follows the item's setting" do
    guardian_item = add_item(@checklist, :attested, "Physical", { statement: "Physical", attested_by: "guardian" })
    manager_item = add_item(@checklist, :attested, "Cleared", { statement: "Cleared", attested_by: "manager" })

    assert ChecklistAttestation.may_attest?(guardian_item, person(:parent), person(:kid))
    assert ChecklistAttestation.may_attest?(guardian_item, person(:kid), person(:kid))
    assert_not ChecklistAttestation.may_attest?(guardian_item, person(:member), person(:kid))
    assert ChecklistAttestation.may_attest?(manager_item, person(:club_manager), person(:kid))
    assert_not ChecklistAttestation.may_attest?(manager_item, person(:club_manager), person(:club_manager)), "never for oneself"
    assert_not ChecklistAttestation.may_attest?(manager_item, person(:parent), person(:kid))
  end

  test "checklist: reads the other checklist's overall; people it doesn't cover are exempt" do
    other = create_world_checklist("Safety check", team: @members)
    add_item(other, :badge, "Safety", { badge_ids: [ @safety.id ] })
    give_badge(:member, @safety)
    refresh(other)
    item = add_item(@checklist, :checklist, "Safety check", { checklist_id: other.id })

    assert_equal "met", evaluate(@checklist, :member, item).status
    assert_equal "not_met", evaluate(@checklist, :member2, item).status
    assert_equal "exempt", evaluate(@checklist, :organizer, item).status
  end

  test "checklist: the fix says who acts on what's left on the other checklist" do
    other = create_world_checklist("Safety cleared", team: @members)
    add_item(other, :badge, "Safety", { badge_ids: [ @safety.id ] })
    confirm = add_item(other, :attested, "Rules", { statement: "Rules read", attested_by: "person" })
    add_item(other, :attested, "Extra", { statement: "Extra", attested_by: "person" }, counts: false)
    ChecklistAttestation.create!(person: person(:member), key: confirm.config["key"], statement: "Rules read", attested_by: person(:member),
      attested_as: "person", attested_at: Time.zone.parse("2026-10-01"))
    item = add_item(@checklist, :checklist, "Season ready", { checklist_id: other.id })

    travel_to Time.zone.parse("2026-11-01 12:00") do
      refresh(other)
      assert_equal "leader", evaluate(@checklist, :member, item).fix["by"], "only the badge is left, and the uncounted item doesn't count"
      assert_equal "person", evaluate(@checklist, :member2, item).fix["by"], "they can confirm the rules themselves"
      assert_equal "See Safety cleared", evaluate(@checklist, :member2, item).fix["label"]
    end
  end

  test "checklist: who acts comes from the same answer as the status, when old stored rows are worked out again" do
    other = create_world_checklist("Safety cleared", team: @members)
    add_item(other, :badge, "Safety", { badge_ids: [ @safety.id ] })
    give_badge(:member, @safety)
    refresh(other)
    item = add_item(@checklist, :checklist, "Season ready", { checklist_id: other.id })
    # The badge goes without telling the checklist, and its rows grow old.
    BadgeAssignment.where(person: person(:member), badge: @safety).delete_all
    ChecklistResult.where(checklist: other).update_all(computed_at: 30.hours.ago)

    result = evaluate(@checklist, :member, item)

    assert_equal "not_met", result.status
    assert_equal "leader", result.fix["by"]
  end

  test "an unregistered kind is unavailable and not met, never a pass" do
    item = add_item(@checklist, :has_login, "Login")
    item.update_columns(kind: "nonesuch")

    result = evaluate(@checklist, :member, item)
    assert_equal "not_met", result.status
    assert_equal "not_met", evaluate(@checklist, :member).status
    assert_includes @checklist.reload.problems.join, "isn't available"
  end

  test "a due date passed marks an unfinished item Missed" do
    item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, due_on: Date.new(2026, 10, 1))

    travel_to(Time.zone.parse("2026-09-15")) { assert_nil evaluate(@checklist, :member, item).label }
    travel_to(Time.zone.parse("2026-10-02")) { assert_equal "Missed", evaluate(@checklist, :member, item).label }
  end
end
