require "test_helper"
require_relative "../support/checklists_world"

class ChecklistRefreshTest < ActiveSupport::TestCase
  include ChecklistsWorld
  include ActiveJob::TestHelper

  setup do
    build_checklists_world
    @checklist = create_world_checklist
    @safety_item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
  end

  test "stores a row per person and item plus the overall" do
    refresh(@checklist)

    covered = Checklists.people_covered_by(@checklist).count
    assert_equal covered * 2, ChecklistResult.where(checklist: @checklist).count
    assert_equal "not_met", stored_status(@checklist, :member, @safety_item)
    assert_equal "not_met", stored_status(@checklist, :member)
  end

  test "a change marks only that person and queues one refresh for the checklist" do
    with_feature do
      refresh(@checklist)
      ChecklistRefresh.delete_all
      clear_enqueued_jobs

      give_badge(:member, @safety)
      give_badge(:member2, @safety)

      assert_equal [ person(:member).id, person(:member2).id ].sort, ChecklistRefresh.where(checklist: @checklist).pluck(:person_id).sort
      assert_enqueued_jobs 1, only: ChecklistRefreshJob
      assert ChecklistResult.find_by(checklist: @checklist, person: person(:member), item: nil).stale?
      assert_not ChecklistResult.find_by(checklist: @checklist, person: person(:kid), item: nil).stale?

      perform_enqueued_jobs(only: ChecklistRefreshJob)
      assert_equal "met", stored_status(@checklist, :member)
      assert_equal "not_met", stored_status(@checklist, :kid)
      assert_empty ChecklistRefresh.where(checklist: @checklist)
    end
  end

  test "a change to a model no kind on the checklist reads marks nothing" do
    with_feature do
      refresh(@checklist)
      ChecklistRefresh.delete_all

      ChecklistAttestation.create!(person: person(:member), key: "x", statement: "X", attested_by: person(:member))
      assert_empty ChecklistRefresh.all
    end
  end

  test "joining the team marks the person for every checklist" do
    with_feature do
      newcomer = Person.create!(first_name: "New", last_name: "Comer")
      Membership.create!(person: newcomer, team: @members)

      assert ChecklistRefresh.exists?(checklist: @checklist, person_id: newcomer.id)
    end
  end

  test "editing an item marks the whole checklist" do
    with_feature do
      @safety_item.update!(label: "Safety training")

      assert ChecklistRefresh.exists?(checklist: @checklist, person_id: nil)
    end
  end

  test "hooks fire once on a change and never on the first computation" do
    runs = []
    Hook.create!(name: "Watch", event: Checklists::STATUS_CHANGED_EVENT, code: "Thread.current[:checklist_hook_runs] << [model.item_id, model.status, model.previous_status]")
    Thread.current[:checklist_hook_runs] = runs
    notified = []
    subscriber = ActiveSupport::Notifications.subscribe(Checklists::STATUS_CHANGED_NOTIFICATION) { |*, payload| notified << payload[:previous_status] }

    refresh(@checklist)
    assert_empty runs, "first computation is silent"

    give_badge(:member, @safety)
    refresh(@checklist)
    assert_equal [ [ @safety_item.id, "met", "not_met" ], [ nil, "met", "not_met" ] ].sort_by(&:to_s), runs.sort_by(&:to_s)
    assert_equal %w[not_met not_met], notified

    refresh(@checklist)
    assert_equal 2, runs.size, "nothing changed, nothing fires"
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    Thread.current[:checklist_hook_runs] = nil
  end

  test "a failing hook doesn't stop the refresh" do
    Hook.create!(name: "Broken", event: Checklists::STATUS_CHANGED_EVENT, code: "raise 'boom'")
    refresh(@checklist)
    give_badge(:member, @safety)

    assert_nothing_raised { refresh(@checklist) }
    assert_equal "met", stored_status(@checklist, :member)
  end

  test "drafts and silent runs fire no hooks" do
    runs = Thread.current[:checklist_hook_runs] = []
    Hook.create!(name: "Watch", event: Checklists::STATUS_CHANGED_EVENT, code: "Thread.current[:checklist_hook_runs] << model.id")
    refresh(@checklist)
    give_badge(:member, @safety)

    changes = Checklists::Refresher.new(@checklist.reload, silent: true).call
    assert_equal 2, changes.size
    assert_empty runs

    @checklist.update!(status: :draft)
    give_badge(:member2, @safety)
    assert_equal 2, refresh(@checklist).size
    assert_empty runs
  ensure
    Thread.current[:checklist_hook_runs] = nil
  end

  test "people who leave lose their rows" do
    refresh(@checklist)
    Membership.find_by(person: person(:rookie)).destroy!
    refresh(@checklist)

    assert_empty ChecklistResult.where(checklist: @checklist, person: person(:rookie))
  end

  test "an overall change marks checklists that require it" do
    with_feature do
      parent = create_world_checklist("Parent")
      add_item(parent, :checklist, "Trip", { checklist_id: @checklist.id })
      refresh(@checklist)
      ChecklistRefresh.delete_all
      BadgeAssignment.skip_callback(:commit, :after, :mark_checklists_for_refresh)
      give_badge(:member, @safety)
      BadgeAssignment.set_callback(:commit, :after, :mark_checklists_for_refresh)

      refresh(@checklist)
      assert ChecklistRefresh.exists?(checklist: parent, person_id: person(:member).id)
    end
  end

  test "the clock refreshes a checklist when its time has come" do
    with_feature do
      @checklist.update!(ends_on: Date.new(2026, 12, 1))
      travel_to(Time.zone.parse("2026-11-20 10:00")) { refresh(@checklist) }
      ChecklistRefresh.delete_all
      assert_equal Time.zone.parse("2026-12-02 00:00:00"), @checklist.reload.next_refresh_at

      travel_to(Time.zone.parse("2026-11-25 10:00")) do
        ChecklistClockJob.perform_now
        assert_equal Time.zone.parse("2026-11-20 10:00"), @checklist.reload.computed_at, "not due yet"
      end
      travel_to(Time.zone.parse("2026-12-02 00:05")) do
        ChecklistClockJob.perform_now
        assert_equal Time.zone.parse("2026-12-02 00:05"), @checklist.reload.computed_at
      end
    end
  end

  test "after Until nothing is scheduled, so the clock leaves it alone" do
    with_feature do
      @checklist.update!(ends_on: Date.new(2026, 10, 1), starts_within_amount: 30, starts_within_unit: "days")
      ChecklistExcuse.create!(item: @safety_item, person: person(:member), reason: "Later", expires_on: Date.new(2026, 12, 1), created_by: person(:club_manager))

      travel_to(Time.zone.parse("2026-09-30 10:00")) do
        assert_equal Time.zone.parse("2026-10-01 00:00"), Checklists::Evaluator.new(@checklist.reload).next_change_at
      end
      travel_to(Time.zone.parse("2026-10-02 10:00")) do
        assert_nil Checklists::Evaluator.new(@checklist.reload).next_change_at
        refresh(@checklist)
        assert_nil @checklist.reload.next_refresh_at
        computed_at = @checklist.computed_at
        ChecklistRefresh.delete_all

        travel 10.minutes
        ChecklistClockJob.perform_now
        assert_equal computed_at, @checklist.reload.computed_at
      end
    end
  end

  test "before Until nothing is scheduled past it" do
    @checklist.update!(ends_on: Date.new(2026, 10, 1))
    travel_to(Time.zone.parse("2026-09-20 10:00")) do
      assert_equal Time.zone.parse("2026-10-02 00:00"), Checklists::Evaluator.new(@checklist.reload).next_change_at
    end
  end

  test "Until freezes results at the end of that day" do
    @checklist.update!(ends_on: Date.new(2026, 10, 1))
    travel_to(Time.zone.parse("2026-10-05")) { give_badge(:member, @safety) }
    @safety_item.update!(config: @safety_item.config.merge("within_dates" => true))

    travel_to(Time.zone.parse("2026-10-10")) do
      assert_equal "not_met", evaluate(@checklist, :member, @safety_item).status, "given after Until"
    end
  end

  test "a badge gained after Until doesn't change the result, and a corrected older record does" do
    @checklist.update!(ends_on: Date.new(2026, 10, 1))
    travel_to(Time.zone.parse("2026-10-05")) do
      assignment = give_badge(:member, @safety)
      assert_equal "not_met", evaluate(@checklist, :member, @safety_item).status, "gained after Until"

      assignment.update!(created_at: Time.zone.parse("2026-09-20 12:00"))
      assert_equal "met", evaluate(@checklist, :member, @safety_item).status, "corrected to before Until"
    end
  end

  test "a stored result freezes at the end of Until in the site's time zone" do
    @checklist.update!(ends_on: Date.new(2026, 12, 1))
    add_rule(@checklist, :include, :team, team_id: @members.id)

    with_settings(feature_checklists: "true", time_zone: "America/New_York") do
      # 8pm on Dec 1 in New York, already Dec 2 in UTC.
      travel_to(Time.utc(2026, 12, 2, 1, 0)) do
        give_badge(:member, @safety)
        refresh(@checklist)
        row = ChecklistResult.find_by!(checklist: @checklist, person: person(:member), item_id: @safety_item.id)
        assert_equal "met", row.status, "still the last day in the site's zone"
        assert_equal Time.utc(2026, 12, 2, 5, 0), @checklist.reload.next_refresh_at
      end
      assert_equal "UTC", Time.zone.name, "the zone goes back afterwards"
    end
  end

  test "a due date on or before Until shows Missed once the last day has gone" do
    @checklist.update!(ends_on: Date.new(2026, 10, 1))
    on_until = add_item(@checklist, :badge, "On Until", { badge_ids: [ @safety.id ] }, due_on: Date.new(2026, 10, 1))
    before = add_item(@checklist, :badge, "Before", { badge_ids: [ @safety.id ] }, due_on: Date.new(2026, 9, 30))
    after = add_item(@checklist, :badge, "After", { badge_ids: [ @safety.id ] }, due_on: Date.new(2026, 11, 1))

    travel_to(Time.zone.parse("2026-10-01 10:00")) do
      assert_nil evaluate(@checklist, :member, on_until).label, "the due day isn't over"
    end
    travel_to(Time.zone.parse("2026-10-10 10:00")) do
      assert_equal "Missed", evaluate(@checklist, :member, on_until).label
      assert_equal "Missed", evaluate(@checklist, :member, before).label
      assert_nil evaluate(@checklist, :member, after).label, "due after Until: capped"
    end
  end

  test "an item requiring another checklist doesn't change after Until" do
    other = create_world_checklist("Other")
    required = add_item(other, :badge, "Safety", { badge_ids: [ @safety.id ] })
    @checklist.update!(ends_on: Date.new(2026, 10, 1))
    item = add_item(@checklist, :checklist, "Other", { checklist_id: other.id })

    travel_to(Time.zone.parse("2026-10-20")) do
      assignment = give_badge(:member, @safety)
      refresh(other)
      assert_equal "met", ChecklistResult.find_by!(checklist: other, person: person(:member), item_id: required.id).status
      assert_equal "not_met", evaluate(@checklist, :member, item).status, "finished the other one after Until"

      assignment.update!(created_at: Time.zone.parse("2026-09-20 12:00"))
      assert_equal "met", evaluate(@checklist, :member, item).status, "a corrected older record still counts"
    end
  end

  test "a frozen checklist reads through a chain of checklists as of its own moment" do
    last = create_world_checklist("Last")
    add_item(last, :badge, "Safety", { badge_ids: [ @safety.id ] })
    middle = create_world_checklist("Middle")
    add_item(middle, :checklist, "Last", { checklist_id: last.id })
    @checklist.update!(ends_on: Date.new(2026, 10, 1))
    item = add_item(@checklist, :checklist, "Middle", { checklist_id: middle.id })

    travel_to(Time.zone.parse("2026-10-20")) do
      give_badge(:member, @safety)
      refresh(last)
      refresh(middle)
      assert_equal "not_met", evaluate(@checklist, :member, item).status
    end
  end

  test "before Until an item requiring another checklist reads its stored results" do
    other = create_world_checklist("Other")
    add_item(other, :badge, "Safety", { badge_ids: [ @safety.id ] })
    @checklist.update!(ends_on: Date.new(2026, 10, 1))
    item = add_item(@checklist, :checklist, "Other", { checklist_id: other.id })
    travel_to(Time.zone.parse("2026-09-20")) do
      give_badge(:member, @safety)
      refresh(other)
      assert_equal "met", evaluate(@checklist, :member, item).status
    end
  end

  test "after Until with results stored, nothing automatic moves them and no hook fires" do
    with_feature do
      runs = Thread.current[:checklist_hook_runs] = []
      Hook.create!(name: "Watch", event: Checklists::STATUS_CHANGED_EVENT, code: "Thread.current[:checklist_hook_runs] << model.id")
      team_item = add_item(@checklist, :team_member, "On the team", { team_ids: [ @members.id ] })
      freeze_results do
        give_badge(:member, @safety)
        Membership.where(person: person(:member)).update_all(created_at: Time.current)
      end
      before = stored_rows(@checklist)
      assert_equal "met", ChecklistResult.find_by!(checklist: @checklist, person: person(:member), item_id: team_item.id).status
      clear_enqueued_jobs

      travel_to(Time.zone.parse("2026-10-05")) do
        Membership.where(person: person(:member)).destroy_all
        BadgeAssignment.where(person: person(:member)).destroy_all
        add_rule(@checklist, :exclude, :person, person_id: person(:member2).id)
        Checklists.mark(@checklist.reload, [ person(:member).id ])
        Checklists.mark(@checklist, :all)
        assert_empty ChecklistRefresh.where(checklist: @checklist), "invalidations are ignored"
        assert_no_enqueued_jobs only: ChecklistRefreshJob

        ChecklistRefresh.create!(checklist: @checklist, created_at: 1.hour.ago)
        ChecklistRefreshJob.perform_now(@checklist.id)
        @checklist.update_columns(next_refresh_at: 1.minute.ago)
        ChecklistClockJob.perform_now
        ChecklistNightlyJob.perform_now
        refresh(@checklist)
      end
      travel_to(Time.zone.parse("2026-10-20")) do
        read = Checklists.status_for(@checklist.reload, [ person(:member) ], viewer: person(:admin))
        assert_equal "met", read[person(:member).id].overall.status, "reads show the stored answer, however old"
      end

      assert_equal before, stored_rows(@checklist)
      assert_empty runs
    end
  ensure
    Thread.current[:checklist_hook_runs] = nil
  end

  test "a frozen checklist isn't marked when a checklist it requires changes" do
    with_feature do
      other = create_world_checklist("Other")
      add_item(other, :badge, "Safety", { badge_ids: [ @safety.id ] })
      add_item(@checklist, :checklist, "Other", { checklist_id: other.id })
      freeze_results { refresh(other) }

      travel_to(Time.zone.parse("2026-10-05")) do
        give_badge(:member, @safety)
        refresh(other)
        assert_not ChecklistRefresh.exists?(checklist: @checklist)
      end
    end
  end

  test "Recompute applies a corrected older record, ignores a badge dated after Until, and drops a leaver" do
    with_feature do
      freeze_results
      travel_to(Time.zone.parse("2026-10-05")) do
        give_badge(:member, @safety)
        give_badge(:member2, @safety).update!(created_at: Time.zone.parse("2026-09-25"))
        Membership.where(person: person(:rookie)).destroy_all

        Checklists::Refresher.new(@checklist.reload, silent: true, recompute: true).call

        status = ->(name) { ChecklistResult.find_by!(checklist: @checklist, person: person(name), item_id: @safety_item.id).status }
        assert_equal "not_met", status[:member], "dated after Until"
        assert_equal "met", status[:member2], "corrected to before Until"
        assert_not ChecklistResult.exists?(checklist: @checklist, person: person(:rookie)), "left the team"
        assert @checklist.reload.results_frozen?, "still frozen afterwards"
      end
    end
  end

  test "moving Until starts over, whether or not the new date has passed" do
    with_feature do
      freeze_results
      travel_to(Time.zone.parse("2026-10-20")) do
        give_badge(:member, @safety).update!(created_at: Time.zone.parse("2026-10-05"))
        @checklist.reload.update!(ends_on: Date.new(2026, 10, 10))
        assert_not @checklist.results_frozen?
        assert ChecklistRefresh.exists?(checklist: @checklist), "the change marks it"

        refresh(@checklist)
        assert_equal "met", ChecklistResult.find_by!(checklist: @checklist, person: person(:member), item_id: @safety_item.id).status
        assert @checklist.reload.results_frozen?

        @checklist.update!(ends_on: Date.new(2026, 12, 1))
        assert_not @checklist.ended?
        assert_not @checklist.results_frozen?
      end
    end
  end

  test "after Until a deleted person's rows go" do
    with_feature do
      @checklist.update!(ends_on: Date.new(2026, 10, 1))
      gone = create_world_person("Gone", @members)
      travel_to(Time.zone.parse("2026-09-20")) { refresh(@checklist) }
      assert ChecklistResult.exists?(checklist: @checklist, person_id: gone.id)

      travel_to(Time.zone.parse("2026-10-05")) do
        gone_id = gone.id
        gone.destroy!
        refresh(@checklist)
        assert_not ChecklistResult.exists?(checklist: @checklist, person_id: gone_id)
        assert_not_includes Checklists.people_covered_by(@checklist).ids, gone_id
      end
    end
  end

  test "setting or moving Until to a date already gone doesn't count older results as frozen" do
    with_feature do
      @checklist.update!(ends_on: nil)
      travel_to(Time.zone.parse("2026-10-20")) do
        refresh(@checklist)
        ChecklistRefresh.delete_all

        @checklist.reload.update!(ends_on: Date.new(2026, 10, 10))
        assert_not @checklist.results_frozen?, "those were live results, not end-of-day ones"
        assert ChecklistRefresh.exists?(checklist: @checklist)

        refresh(@checklist)
        assert @checklist.reload.results_frozen?
        ChecklistRefresh.delete_all

        @checklist.update!(ends_on: Date.new(2026, 10, 5))
        assert_not @checklist.results_frozen?, "moved earlier"
        assert ChecklistRefresh.exists?(checklist: @checklist)
      end
    end
  end

  test "the first refresh of an ended checklist with no rows covers everyone" do
    @checklist.update!(ends_on: Date.new(2026, 10, 1))
    everyone = Checklists.people_covered_by(@checklist).ids
    assert_operator everyone.size, :>, 1

    travel_to(Time.zone.parse("2026-10-05")) do
      Checklists::Refresher.new(@checklist.reload).call([ person(:member).id ])
      assert_equal everyone.sort, ChecklistResult.where(checklist: @checklist, item_id: nil).pluck(:person_id).sort
    end
  end

  test "reading one person of an ended checklist with no rows stores everyone" do
    @checklist.update!(ends_on: Date.new(2026, 10, 1))
    everyone = Checklists.people_covered_by(@checklist).ids

    travel_to(Time.zone.parse("2026-10-05")) do
      Checklists.status_for(@checklist.reload, [ person(:member) ], viewer: person(:admin))
      assert_equal everyone.sort, ChecklistResult.where(checklist: @checklist, item_id: nil).pluck(:person_id).sort
    end
  end

  test "an ended checklist whose results were pruned isn't frozen" do
    freeze_results
    ChecklistResult.where(checklist: @checklist).delete_all
    travel_to(Time.zone.parse("2026-10-05")) { assert_not @checklist.reload.results_frozen? }
  end

  test "with no Until, results stay live" do
    @checklist.update!(ends_on: nil)
    travel_to(Time.zone.parse("2030-01-05")) do
      give_badge(:member, @safety)
      assert_equal "met", evaluate(@checklist, :member, @safety_item).status
      assert_equal Time.current, Checklists::Context.new(@checklist).as_of
    end
  end

  test "an item's own Until doesn't freeze anything, and the checklist's caps it" do
    @checklist.update!(ends_on: Date.new(2026, 10, 1))
    late = add_item(@checklist, :badge, "Late", { badge_ids: [ @safety.id ] }, ends_on: Date.new(2026, 12, 1))
    window = Checklists::Context.new(@checklist).window_for(late)
    assert_equal Date.new(2026, 10, 1), window.ends_on

    @checklist.update!(ends_on: Date.new(2027, 6, 30))
    early = add_item(@checklist, :badge, "Early", { badge_ids: [ @safety.id ] }, ends_on: Date.new(2026, 10, 1))
    travel_to(Time.zone.parse("2026-10-05")) do
      assert_equal Date.new(2026, 10, 1), Checklists::Context.new(@checklist.reload).window_for(early).ends_on
      assert_equal Time.current, Checklists::Context.new(@checklist).as_of, "only the checklist's Until freezes"
    end
  end

  test "the nightly job repairs a missed row" do
    with_feature do
      refresh(@checklist)
      ChecklistResult.where(checklist: @checklist, person: person(:member)).delete_all
      BadgeAssignment.skip_callback(:commit, :after, :mark_checklists_for_refresh)
      give_badge(:member2, @safety)
      BadgeAssignment.set_callback(:commit, :after, :mark_checklists_for_refresh)

      ChecklistNightlyJob.perform_now
      assert_equal "not_met", stored_status(@checklist, :member)
      assert_equal "met", stored_status(@checklist, :member2)
    end
  end

  test "reads compute missing people and recompute rows that are too old" do
    statuses = Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:admin))
    assert_equal "not_met", statuses[person(:member).id].overall.status
    assert ChecklistResult.exists?(checklist: @checklist, person: person(:member), item: nil)

    BadgeAssignment.skip_callback(:commit, :after, :mark_checklists_for_refresh)
    give_badge(:member, @safety)
    BadgeAssignment.set_callback(:commit, :after, :mark_checklists_for_refresh)
    travel 25.hours do
      statuses = Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:admin))
      assert_equal "met", statuses[person(:member).id].overall.status
      assert ChecklistRefresh.exists?(checklist: @checklist, person_id: person(:member).id), "marked so the job reports it"
    end
  end

  test "with the feature off: no marks, no refresh rows, no job work" do
    refresh(@checklist)
    ChecklistRefresh.delete_all
    clear_enqueued_jobs

    give_badge(:member, @safety)
    @safety_item.update!(label: "Renamed")
    assert_empty ChecklistRefresh.all
    assert_no_enqueued_jobs

    computed_at = @checklist.reload.computed_at
    ChecklistRefresh.create!(checklist: @checklist, created_at: 1.hour.ago)
    @checklist.update_columns(next_refresh_at: 1.minute.ago)
    ChecklistClockJob.perform_now
    ChecklistNightlyJob.perform_now
    ChecklistRefreshJob.perform_now(@checklist.id)
    assert_equal computed_at, @checklist.reload.computed_at
    assert_equal "not_met", stored_status(@checklist, :member)
  end

  test "one failing checklist doesn't stop the clock job for the others" do
    with_feature do
      broken = create_world_checklist("Broken")
      add_item(broken, :has_login, "Login")
      [ broken, @checklist ].each { |checklist| checklist.update_columns(next_refresh_at: 1.minute.ago) }
      failing = Class.new(Checklists::Refresher) do
        def call(*)
          raise "boom" if checklist.title == "Broken"

          super
        end
      end
      original = Checklists.send(:remove_const, :Refresher)
      Checklists.const_set(:Refresher, failing)

      ChecklistClockJob.perform_now
      assert_not_nil @checklist.reload.computed_at
      assert_nil broken.reload.computed_at
    ensure
      Checklists.send(:remove_const, :Refresher)
      Checklists.const_set(:Refresher, original)
    end
  end

  test "a failed refresh puts its marks back" do
    with_feature do
      Checklists.mark(@checklist, [ person(:member).id ])
      @safety_item.update_columns(kind: "badge")
      Checklists::Evaluator.class_eval { alias_method :original_call, :call; def call(*) = raise("boom") }

      assert_raises(RuntimeError) { ChecklistRefreshJob.perform_now(@checklist.id) }
      assert ChecklistRefresh.exists?(checklist: @checklist, person_id: person(:member).id)
    ensure
      Checklists::Evaluator.class_eval { alias_method :call, :original_call; remove_method :original_call }
    end
  end

  test "asking about someone the checklist doesn't cover writes nothing" do
    refresh(@checklist)
    computed_at = @checklist.reload.computed_at

    queries = count_queries do
      statuses = Checklists.status_for(@checklist, [ person(:kid), person(:outsider) ], viewer: person(:parent))
      assert_equal [ person(:kid).id ], statuses.keys
    end
    assert_equal computed_at, @checklist.reload.computed_at
    assert_operator queries, :<=, 20
  end

  test "status_for stays bounded for a guardian and a grant holder over 200 people" do
    team = Team.create!(name: "Big", team_type: team_types(:one), parent: @club)
    ids = Person.insert_all(200.times.map { |index| { first_name: "P#{index}", last_name: "Big", display_name: "P#{index} Big" } }, returning: :id).rows.flatten
    Membership.insert_all(ids.map { |id| { person_id: id, team_id: team.id } })
    big = create_world_checklist("Big", team: @club)
    add_item(big, :badge, "Safety", { badge_ids: [ @safety.id ] })
    add_item(big, :has_login, "Login", {}, read_level: "self_and_leaders")
    add_item(big, :team_member, "Team", { team_ids: [ team.id ] })
    big.checklist_grants.create!(badge: @viewer_badge, item_ids: [ big.checklist_items.first.id ], access: :full)
    give_badge(:outsider, @viewer_badge)
    refresh(big)
    people = Person.where(id: ids).to_a + [ person(:kid) ]

    fresh = -> { Checklist.find(big.id) }
    guardian = count_queries { assert_equal [ person(:kid).id ], Checklists.status_for(fresh.call, people, viewer: person(:parent)).keys }
    granted = count_queries { assert_equal 201, Checklists.status_for(fresh.call, people, viewer: person(:outsider)).size }
    assert_operator guardian, :<=, 20
    assert_operator granted, :<=, 20

    few = count_queries { Checklists.status_for(fresh.call, people.first(10), viewer: person(:outsider)) }
    assert_equal few, granted, "the same number of queries whatever the number of people"
  end

  test "status_for reads 200 people and 10 items in a bounded number of queries" do
    team = Team.create!(name: "Big", team_type: team_types(:one), parent: @club)
    rows = 200.times.map { |index| { first_name: "P#{index}", last_name: "Big", display_name: "P#{index} Big", created_at: Time.current, updated_at: Time.current } }
    ids = Person.insert_all(rows, returning: :id).rows.flatten
    Membership.insert_all(ids.map { |id| { person_id: id, team_id: team.id, created_at: Time.current, updated_at: Time.current } })
    big = create_world_checklist("Big", team: team)
    group = add_item(big, :any_of, "Either")
    add_item(big, :badge, "Safety", { badge_ids: [ @safety.id ] }, parent: group)
    add_item(big, :has_login, "Login", {}, parent: group)
    add_item(big, :badge, "Safety", { badge_ids: [ @safety.id ] })
    add_item(big, :team_member, "Team", { team_ids: [ team.id ] })
    add_item(big, :has_login, "Login")
    add_item(big, :age, "Age", { min: 10 })
    add_item(big, :attested, "Handbook", { statement: "Handbook read" })
    add_item(big, :badge, "Viewer", { badge_ids: [ @viewer_badge.id ] })
    add_item(big, :team_member, "Club", { team_ids: [ @club.id ] })

    evaluate_queries = count_queries { refresh(big) }
    assert_operator evaluate_queries, :<, 80, "refresh of 200 people"

    people = Person.where(id: ids).to_a
    queries = count_queries { Checklists.status_for(big, people, viewer: person(:admin)) }
    assert_operator queries, :<=, 8
    assert_equal 200, Checklists.status_for(big, people, viewer: person(:admin)).size
  end

  private

  # Until Oct 1: whatever the block does happens before it, and the one
  # refresh after it stores the end-of-day answers.
  def freeze_results
    @checklist.update!(ends_on: Date.new(2026, 10, 1))
    travel_to(Time.zone.parse("2026-09-20")) { yield if block_given? }
    travel_to(Time.zone.parse("2026-10-02 00:05")) { refresh(@checklist) }
    assert @checklist.reload.results_frozen?
    ChecklistRefresh.delete_all
  end

  def stored_rows(checklist)
    ChecklistResult.where(checklist: checklist).order(:id).pluck(:id, :person_id, :item_id, :status, :label, :summary, :stale, :computed_at)
  end

  # Queries run by the block, with the query cache off so earlier calls
  # don't hide any.
  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached] }
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    end
    count
  end
end
