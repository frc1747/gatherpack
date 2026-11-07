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

    assert_not doomed.destroy, "the item protects the badge"
    assert_match "Used by the checklist Trip", doomed.errors.full_messages.to_sentence

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
