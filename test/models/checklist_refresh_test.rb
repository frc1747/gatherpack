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
      @checklist.update!(cutoff_on: Date.new(2026, 12, 1))
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

  test "a cutoff freezes results at the end of that day" do
    @checklist.update!(cutoff_on: Date.new(2026, 10, 1))
    travel_to(Time.zone.parse("2026-10-05")) { give_badge(:member, @safety) }
    @safety_item.update!(config: @safety_item.config.merge("within_dates" => true))

    travel_to(Time.zone.parse("2026-10-10")) do
      assert_equal "not_met", evaluate(@checklist, :member, @safety_item).status, "given after the cutoff"
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

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
