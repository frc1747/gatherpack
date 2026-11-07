require "test_helper"
require_relative "../support/checklists_world"

class ChecklistAttendanceTest < ActiveSupport::TestCase
  include ChecklistsWorld

  setup do
    build_checklists_world
    @checklist = create_world_checklist("Attendance", starts_on: Date.new(2026, 5, 1), ends_on: Date.new(2027, 4, 30))
    @period = TimeClockPeriod.create!(name: "Season", start_time: Date.new(2026, 4, 1), end_time: Date.new(2027, 5, 31), permission: :added_by_admin)
  end

  test "credit is punched time overlapping meetings: leaving early costs, staying late adds nothing" do
    meeting("2026-10-05")
    punch(:member, "2026-10-05", "18:00", "19:00")
    punch(:member2, "2026-10-05", "17:00", "21:00")
    punch(:kid, "2026-10-05", "18:00", "19:00")
    punch(:kid, "2026-10-05", "18:30", "20:00")
    item = attendance([ { name: "Fall", share: "60" } ])

    travel_to Time.zone.parse("2026-10-10 12:00") do
      left_early = evaluate(@checklist, :member, item)
      assert_equal "not_met", left_early.status
      assert_equal "Below minimum", left_early.label
      assert_equal({ "meetings" => 1, "held" => 1, "credited" => 1.0, "percent" => 50.0, "extra" => 0.0 }, left_early.measures)
      assert_equal "✗ Fall: 50% of 2 h (needs 60%)", left_early.detail

      stayed_late = evaluate(@checklist, :member2, item)
      assert_equal "met", stayed_late.status
      assert_equal 2.0, stayed_late.measures["credited"]
      assert_equal 2.0, stayed_late.measures["extra"]
      assert_equal 100.0, stayed_late.measures["percent"], "never above 100%"

      overlapping = evaluate(@checklist, :kid, item)
      assert_equal 2.0, overlapping.measures["credited"], "overlapping punches count once"
      assert_equal "met", overlapping.status

      assert_equal "not_met", evaluate(@checklist, :rookie, item).status
      assert_equal 0, evaluate(@checklist, :rookie, item).measures["meetings"]
    end
  end

  test "pooled rules count each meeting's hours at its own rule's share" do
    summer = (1..10).map { |week| meeting((Date.new(2026, 5, 4) + week.weeks).iso8601) }
    fall = (1..5).map { |week| meeting((Date.new(2026, 9, 7) + week.weeks).iso8601) }
    [ fall[0], fall[1] ].each { |event| punch_at(:member, event) }
    [ summer[0], fall[0] ].each { |event| punch_at(:member2, event) }
    punch_at(:kid, summer[0])
    rules = [ { name: "Summer", starts_on: "2026-05-01", ends_on: "2026-08-31", share: "10", with: "Fall" },
      { name: "Fall", starts_on: "2026-09-01", ends_on: "2026-12-31", share: "20" } ]
    item = attendance(rules)

    travel_to Time.zone.parse("2027-01-02 12:00") do
      # The pool needs 20 h at 10% plus 10 h at 20%: 4 h, not 30 h at one share.
      assert_equal "met", evaluate(@checklist, :member, item).status, "fall time makes up for summer"
      assert_equal "met", evaluate(@checklist, :member2, item).status
      kid = evaluate(@checklist, :kid, item)
      assert_equal "not_met", kid.status
      assert_equal "✗ Summer and Fall: 2 h of 30 h (needs 4 h)", kid.detail
    end

    item.update!(config: item.config.merge("rule_1_with" => nil))
    travel_to Time.zone.parse("2027-01-02 12:00") do
      alone = evaluate(@checklist, :member, item)
      assert_equal "not_met", alone.status, "judged on its own, summer fails"
      assert_equal "✗ Summer: 0% of 20 h (needs 10%); ✓ Fall: 40% of 10 h (needs 20%)", alone.detail
    end
  end

  test "a weekly rule fails when one week falls short" do
    week1 = [ meeting("2027-01-11"), meeting("2027-01-13") ]
    week2 = [ meeting("2027-01-18"), meeting("2027-01-20") ]
    week1.each { |event| punch_at(:member, event) }
    punch_at(:member2, week1[0])
    punch_at(:member2, week2[0])
    item = attendance([ { name: "Build", starts_on: "2027-01-01", ends_on: "2027-04-30", share: "40", weekly: "1" } ])

    travel_to Time.zone.parse("2027-01-25 12:00") do
      result = evaluate(@checklist, :member, item)
      assert_equal "not_met", result.status
      assert_equal "✓ Build, week of Jan 11: 100% of 4 h (needs 40%); ✗ Build, week of Jan 18: 0% of 4 h (needs 40%)", result.detail
      assert_equal "met", evaluate(@checklist, :member2, item).status
    end
  end

  test "extra hours make up missed meeting time within the group, never above 100%" do
    meeting("2026-10-05")
    punch(:member, "2026-10-05", "15:00", "16:00")
    punch(:member2, "2026-10-05", "10:00", "16:00")
    punch(:member2, "2026-10-05", "18:00", "19:00")
    item = attendance([ { name: "Fall", share: "50" } ])

    travel_to Time.zone.parse("2026-10-10 12:00") do
      assert_equal "not_met", evaluate(@checklist, :member, item).status

      item.update!(config: item.config.merge("extra_hours_count" => true))
      assert_equal "met", evaluate(@checklist, :member, item).status
      capped = evaluate(@checklist, :member2, item)
      assert_equal "met", capped.status
      assert_equal "✓ Fall: 100% of 2 h (needs 50%)", capped.detail
      assert_equal 1.0, capped.measures["credited"], "extra time isn't meeting time"
      assert_equal 6.0, capped.measures["extra"]
    end
  end

  test "leeway lets someone just short of a minimum pass" do
    meeting("2026-10-05")
    TimeClockPunch.create!(person: person(:member), time_clock_period: @period, created_by: person(:admin),
      start_time: Time.zone.parse("2026-10-05 18:00"), end_time: Time.zone.parse("2026-10-05 18:59:30"))
    item = attendance([ { name: "Fall", share: "50" } ])

    travel_to Time.zone.parse("2026-10-10 12:00") do
      assert_equal "met", evaluate(@checklist, :member, item).status, "default leeway is one minute"

      item.update!(config: item.config.merge("leeway_minutes" => 0))
      assert_equal "not_met", evaluate(@checklist, :member, item).status
    end
  end

  test "meetings at the edges of the dates count by the day in the time zone" do
    Time.use_zone("America/New_York") do
      inside_end = meeting("2027-04-30", "18:00", "21:00")
      meeting("2026-04-30", "20:00", "22:00")
      summer_edge = meeting("2026-08-31", "19:00", "21:00")
      punch_at(:member, inside_end)
      punch_at(:member, summer_edge)
      item = attendance([ { name: "Summer", starts_on: "2026-05-01", ends_on: "2026-08-31", share: "50" },
        { name: "Spring", starts_on: "2027-01-01", ends_on: "2027-04-30", share: "50" } ])

      travel_to Time.zone.parse("2027-05-02 12:00") do
        result = evaluate(@checklist, :member, item)
        assert_equal 2, result.measures["held"], "the last day's evening meeting counts; the evening before the start doesn't"
        assert_equal "met", result.status
        assert_equal "✓ Summer: 100% of 2 h (needs 50%); ✓ Spring: 100% of 3 h (needs 50%)", result.detail
      end
    end
  end

  test "an excused meeting leaves the person's required and credited hours" do
    first = meeting("2026-10-05")
    missed = meeting("2026-10-07")
    punch_at(:member, first)
    item = attendance([ { name: "Fall", share: "60" } ])

    travel_to Time.zone.parse("2026-10-10 12:00") do
      assert_equal "not_met", evaluate(@checklist, :member, item).status

      ChecklistExcuse.create!(item: item, person: person(:member), event: missed, reason: "Ill", created_by: person(:club_manager))
      result = evaluate(@checklist, :member, item)
      assert_equal "met", result.status
      assert_equal 1, result.measures["held"]
      assert_equal "✓ Fall: 100% of 2 h (needs 60%); Excused from Meeting (Oct 7)", result.detail
      assert_equal "not_met", evaluate(@checklist, :member2, item).status, "excuses only the person"

      ChecklistExcuse.create!(item: item, person: person(:member), event: first, reason: "Ill", created_by: person(:club_manager))
      assert_equal "exempt", evaluate(@checklist, :member, item).status, "nothing left to judge"
    end
  end

  test "an excused meeting the person came to leaves their credit too" do
    first = meeting("2026-10-05")
    second = meeting("2026-10-07")
    punch_at(:member, first)
    punch_at(:member, second)
    item = attendance([ { name: "Fall", share: "60" } ])
    ChecklistExcuse.create!(item: item, person: person(:member), event: second, reason: "Counted elsewhere", created_by: person(:club_manager))

    travel_to Time.zone.parse("2026-10-10 12:00") do
      result = evaluate(@checklist, :member, item)
      assert_equal 2.0, result.measures["credited"]
      assert_equal "✓ Fall: 100% of 2 h (needs 60%); Excused from Meeting (Oct 7)", result.detail
    end
  end

  test "no meetings yet is not counted" do
    meeting("2026-10-05")
    item = attendance([ { name: "Fall", share: "60" } ])

    travel_to Time.zone.parse("2026-10-05 19:00") do
      result = evaluate(@checklist, :member, item)
      assert_equal "exempt", result.status
      assert_equal "No meetings yet", result.label
      assert_equal "met", evaluate(@checklist, :member, nil).status, "doesn't count against anyone"
    end
  end

  test "judge after N meetings shows Almost until enough are held" do
    meetings = (0..2).map { |day| meeting((Date.new(2026, 10, 5) + day.days).iso8601) }
    punch_at(:member, meetings[0])
    item = attendance([ { name: "Fall", share: "60", judge_after: "3" } ])

    travel_to Time.zone.parse("2026-10-06 21:00") do
      result = evaluate(@checklist, :member, item)
      assert_equal "pending", result.status
      assert_equal "Counted after 3 meetings; 2 held", result.summary
    end
    travel_to Time.zone.parse("2026-10-08 12:00") do
      assert_equal "not_met", evaluate(@checklist, :member, item).status
    end

    item.update!(config: item.config.merge("rule_1_judge_after" => 0))
    travel_to Time.zone.parse("2026-10-05 21:00") do
      assert_equal "met", evaluate(@checklist, :member, item).status, "default 0 judges from the first meeting"
    end
  end

  test "a batch gives the same answers as one person at a time" do
    events = (0..5).map { |day| meeting((Date.new(2026, 10, 5) + day.weeks).iso8601) }
    events.each_with_index { |event, index| punch_at(:member, event) if index.even? }
    punch_at(:member2, events[1])
    item = attendance([ { name: "Fall", share: "40", weekly: "1" } ])
    ChecklistExcuse.create!(item: item, person: person(:member2), event: events[2], reason: "Away", created_by: person(:club_manager))
    names = %i[member member2 kid rookie]

    travel_to Time.zone.parse("2026-12-01 12:00") do
      batch = Checklists::Evaluator.new(@checklist.reload).call(names.map { |name| person(name).id })
      names.each do |name|
        single = evaluate(@checklist, name, item)
        assert_equal single.to_h, batch.dig(person(name).id, item.id).to_h, name.to_s
      end
    end
  end

  test "parity with the eligibility Page on a fixed dataset" do
    days = %w[2026-05-06 2026-06-10 2026-07-15 2026-08-19 2026-09-09 2026-10-14 2026-11-11 2026-12-09
      2027-01-11 2027-01-13 2027-01-18 2027-01-20 2027-02-01 2027-02-03]
    meetings = days.map { |day| meeting(day) }
    meeting("2027-05-20")
    plan = {
      member: [ [ 5, "18:00", "20:00" ], [ 6, "18:00", "20:00" ], [ 8, "18:00", "20:00" ], [ 10, "18:00", "20:00" ], [ 12, "18:00", "20:00" ] ],
      member2: [ [ 0, "17:00", "21:00" ], [ 8, "18:00", "19:00" ], [ 9, "18:30", "20:00" ], [ 10, "18:00", "19:30" ], [ 13, "18:00", "20:00" ] ],
      kid: [ [ 4, "18:00", "18:45" ], [ 8, "18:00", "20:00" ], [ 9, "18:00", "20:00" ], [ 10, "18:00", "20:00" ], [ 11, "18:00", "20:00" ], [ 12, "18:00", "20:00" ], [ 13, "18:00", "20:00" ] ],
      rookie: [ [ 1, "18:00", "20:00" ], [ 1, "19:00", "22:00" ] ],
      organizer: []
    }
    plan.each { |name, punches| punches.each { |index, from, to| punch(name, days[index], from, to) } }
    punch(:organizer, "2026-10-20", "10:00", "14:00")
    page_rules = [
      { name: "Off-Season Summer", months: 5..8, share: 0.10, weekly: false, pool: "Off-Season" },
      { name: "Off-Season Fall", months: 9..12, share: 0.20, weekly: false, pool: "Off-Season" },
      { name: "Build/Competition", months: 1..4, share: 0.40, weekly: true }
    ]
    rules = [ { name: "Off-Season Summer", starts_on: "2026-05-01", ends_on: "2026-08-31", share: "10", with: "Off-Season Fall" },
      { name: "Off-Season Fall", starts_on: "2026-09-01", ends_on: "2026-12-31", share: "20" },
      { name: "Build/Competition", starts_on: "2027-01-01", ends_on: "2027-04-30", share: "40", weekly: "1" } ]

    seen = Set.new
    [ false, true ].each do |extra_hours_count|
      item = attendance(rules, extra_hours_count: extra_hours_count, label: "Attendance #{extra_hours_count}")
      travel_to Time.zone.parse("2027-05-10 12:00") do
        page = page_attendance(page_rules, extra_hours_count)
        plan.each_key do |name|
          expected = page.call(person(name))
          result = evaluate(@checklist, name, item)
          seen << [ extra_hours_count, result.status ]
          assert_equal({ met: "met", needs: "not_met", none: "exempt" }.fetch(expected[:status]), result.status, "#{name}, extra #{extra_hours_count}")
          assert_equal expected[:meetings], result.measures["meetings"], name.to_s
          assert_equal expected[:credited], result.measures["credited"], name.to_s
          assert_equal expected[:extra], result.measures["extra"], name.to_s
          assert_in_delta expected[:pct], result.measures["percent"], 0.05, name.to_s
          assert_equal expected[:passes], result.detail.scan("✓").size, name.to_s
        end
        assert_equal meetings.size, evaluate(@checklist, :member, item).measures["held"]
      end
    end
    assert_includes seen, [ false, "met" ]
    assert_includes seen, [ false, "not_met" ]
    assert_includes seen, [ true, "met" ]
  end

  test "the rules are checked when saved" do
    item = @checklist.checklist_items.new(kind: "attendance", label: "Attendance")
    item.config_params = {}
    assert_not item.valid?
    assert_includes item.errors[:base], "Add at least one rule with a share of meeting hours"

    item.config_params = { rule_1_name: "Summer", rule_1_share: "10", rule_1_with: "Autumn" }
    assert_not item.valid?
    assert_includes item.errors[:base].join, "no other rule has that name"

    item.config_params = { rule_1_name: "Summer", rule_1_share: "10", rule_1_with: "Fall", rule_2_name: "Fall", rule_2_share: "20", rule_2_weekly: "1" }
    assert_not item.valid?
    assert_includes item.errors[:base], "Rules counted together must all be weekly, or none of them"

    item.config_params = { rule_1_name: "Summer", rule_1_share: "110" }
    assert_not item.valid?

    item.config_params = { rule_1_name: "Summer", rule_1_share: "10", rule_1_with: "Fall", rule_2_name: "Fall", rule_2_share: "20" }
    assert item.valid?, item.errors.full_messages.to_sentence
    assert_equal "At least 10% of meeting hours in Summer, counted together with Fall; 20% of meeting hours in Fall, counted together with Summer", item.describe
  end

  test "a named period narrows the meetings, and a deleted one is a problem" do
    other = TimeClockPeriod.create!(name: "Other", start_time: Date.new(2026, 4, 1), end_time: Date.new(2027, 5, 31), permission: :added_by_admin)
    meeting("2026-10-05")
    Event.create!(name: "Elsewhere", event_type: event_types(:one), team: @club, time_clock_period: other,
      start_time: Time.zone.parse("2026-10-06 18:00"), end_time: Time.zone.parse("2026-10-06 20:00"))
    item = attendance([ { name: "Fall", share: "50" } ], period_id: @period.id)

    travel_to Time.zone.parse("2026-10-10 12:00") do
      assert_equal 1, evaluate(@checklist, :member, item).measures["held"]
      item.update!(config: item.config.merge("period_id" => nil))
      assert_equal 2, evaluate(@checklist, :member, item).measures["held"], "every overlapping period by default"
    end

    item.update!(config: item.config.merge("period_id" => @period.id))
    assert_not @period.destroy, "the item protects the period"
    item.update_columns(config: item.config.merge("period_id" => SecureRandom.uuid))
    assert_includes @checklist.reload.problems.join, "was deleted"
  end

  test "the next refresh is just after the next meeting ends" do
    meeting("2026-10-05")
    upcoming = meeting("2026-10-07")
    item = attendance([ { name: "Fall", share: "50" } ])

    travel_to Time.zone.parse("2026-10-06 12:00") do
      context = Checklists::Context.new(@checklist.reload)
      assert_equal upcoming.end_time + 1.second, Checklists::Kinds::Attendance.next_change_at(item, context)
    end
  end

  test "a punch marks only that person's results for refresh" do
    meeting("2026-10-05")
    attendance([ { name: "Fall", share: "50" } ])

    with_feature do
      travel_to Time.zone.parse("2026-10-10 12:00") do
        refresh(@checklist, silent: true)
        punch(:member, "2026-10-05", "18:00", "20:00")

        assert ChecklistResult.where(checklist: @checklist, person: person(:member)).all?(&:stale)
        assert_not ChecklistResult.where(checklist: @checklist, person: person(:member2)).any?(&:stale)
      end
    end
  end

  test "copying shifts the rules' dates" do
    attendance([ { name: "Summer", starts_on: "2026-05-01", ends_on: "2026-08-31", share: "10" } ])

    changes = Checklists::Copier.new(@checklist.reload).date_changes.map { |change| [ change.label, change.proposed ] }
    assert_includes changes, [ "Attendance: rule 1 starts on", Date.new(2027, 5, 1) ]
    assert_includes changes, [ "Attendance: rule 1 ends on", Date.new(2027, 8, 31) ]
  end

  private

  def meeting(day, from = "18:00", to = "20:00")
    Event.create!(name: "Meeting", event_type: event_types(:one), team: @club, time_clock_period: @period,
      start_time: Time.zone.parse("#{day} #{from}"), end_time: Time.zone.parse("#{day} #{to}"))
  end

  def punch(name, day, from, to)
    TimeClockPunch.create!(person: person(name), time_clock_period: @period, created_by: person(:admin),
      start_time: Time.zone.parse("#{day} #{from}"), end_time: Time.zone.parse("#{day} #{to}"))
  end

  def punch_at(name, event)
    TimeClockPunch.create!(person: person(name), time_clock_period: @period, created_by: person(:admin),
      start_time: event.start_time, end_time: event.end_time)
  end

  def attendance(rules, label: "Attendance", **options)
    config = options.transform_keys(&:to_s)
    rules.each.with_index(1) { |rule, number| rule.each { |key, value| config["rule_#{number}_#{key}"] = value } }
    add_item(@checklist, :attendance, label, config)
  end

  # The eligibility Page's attendance (pages/eligibility-report.html.erb,
  # lines 146-200), as written, over the test period.
  def page_attendance(attendance_rules, extra_hours_count)
    period = @period
    punches = TimeClockPunch.where(time_clock_period: period).where.not(end_time: nil).to_a
    merge = ->(intervals) do
      intervals.sort.each_with_object([]) do |(st, et), merged|
        if merged.any? && st <= merged.last[1]
          merged.last[1] = [ merged.last[1], et ].max
        else
          merged << [ st, et ]
        end
      end
    end
    seconds_to_hours = ->(seconds) { (seconds / 3600.0 * 20).round / 20.0 }
    overlap = ->(a, b) do
      a.sum { |ast, aet| b.sum { |bst, bet| [ [ aet, bet ].min - [ ast, bst ].max, 0 ].max } }
    end
    meetings = period.events.where.not(start_time: nil).where.not(end_time: nil).where("end_time < ?", Time.current).order(:start_time).to_a
    meeting_intervals = merge.call(meetings.map { |e| [ e.start_time, e.end_time ] })
    available_hours = seconds_to_hours.call(meeting_intervals.sum { |st, et| et - st })
    rule_for = ->(time) { attendance_rules.find { |r| r[:months].include?(time.in_time_zone.month) } }
    group_key = ->(time) do
      rule = rule_for.call(time)
      next nil unless rule
      rule[:weekly] ? [ rule[:name], time.in_time_zone.to_date.beginning_of_week ] : [ rule[:pool] || rule[:name], nil ]
    end
    groups = meetings.group_by { |e| group_key.call(e.start_time) }.reject { |key, _| key.nil? }.map do |(name, week), events|
      intervals = merge.call(events.map { |e| [ e.start_time, e.end_time ] })
      by_rule = events.group_by { |e| rule_for.call(e.start_time) }
      needed = by_rule.sum { |rule, evs| merge.call(evs.map { |e| [ e.start_time, e.end_time ] }).sum { |st, et| et - st } * rule[:share] }
      { key: [ name, week ], intervals: intervals, held: intervals.sum { |st, et| et - st }, needed: needed }
    end
    by_person = punches.group_by(&:person_id)

    ->(person) do
      mine = merge.call((by_person[person.id] || []).map { |p| [ p.start_time, p.end_time ] })
      credited = overlap.call(mine, meeting_intervals)
      extra_by_group = Hash.new(0)
      mine.each do |st, et|
        key = group_key.call(st)
        extra_by_group[key] += (et - st) - overlap.call([ [ st, et ] ], meeting_intervals) if key
      end
      checks = groups.map do |g|
        got = overlap.call(mine, g[:intervals])
        got += [ extra_by_group[g[:key]], g[:held] - got ].min if extra_hours_count
        { pass: got + 1 >= g[:needed] }
      end
      {
        meetings: meetings.count { |e| overlap.call(mine, [ [ e.start_time, e.end_time ] ]) > 0 },
        credited: seconds_to_hours.call(credited),
        extra: [ seconds_to_hours.call(mine.sum { |st, et| et - st } - credited), 0 ].max,
        pct: available_hours > 0 ? seconds_to_hours.call(credited) / available_hours * 100 : nil,
        status: checks.empty? ? :none : (checks.all? { |c| c[:pass] } ? :met : :needs),
        passes: checks.count { |c| c[:pass] }
      }
    end
  end
end
