require "test_helper"
require_relative "../support/checklists_world"

class ChecklistMeetingExcusesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    build_checklists_world
    @checklist = create_world_checklist("Trip", starts_on: Date.new(2026, 9, 1))
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @period = TimeClockPeriod.create!(name: "Season", start_time: Date.new(2026, 9, 1), end_time: Date.new(2027, 6, 30), permission: :added_by_admin)
    @attended = meeting("Kickoff", "2026-10-05")
    @missed = meeting("Build night", "2026-10-07")
    TimeClockPunch.create!(person: person(:member), time_clock_period: @period, created_by: person(:admin),
      start_time: @attended.start_time, end_time: @attended.end_time)
    @item = add_item(@checklist, :attendance, "Attendance", { rule_1_name: "Fall", rule_1_share: "60" })
    @badge_item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
  end

  test "an attendance item's excuse link offers its meetings" do
    with_feature do
      travel_to Time.zone.parse("2026-10-10 12:00") do
        sign_in person(:club_manager).user
        get new_checklist_checklist_excuse_path(@checklist, item_id: @item.id, person_id: person(:member).id)
        assert_response :success
        assert_match "Excuse #{person(:member).display_name} from a meeting", response.body
        assert_match "Build night", response.body
        assert_match "there 0 of 2 h", response.body
        assert_match "there 2 of 2 h", response.body

        get new_checklist_checklist_excuse_path(@checklist, item_id: @item.id, person_id: person(:member).id, whole: 1)
        assert_response :success
        assert_no_match "from a meeting", response.body

        get new_checklist_checklist_excuse_path(@checklist, item_id: @badge_item.id, person_id: person(:member).id)
        assert_no_match "from a meeting", response.body, "other kinds keep the whole-item form"
      end
    end
  end

  test "a manager excuses one meeting, which leaves the person's hours" do
    give_badge(:member, @safety)
    with_feature do
      travel_to Time.zone.parse("2026-10-10 12:00") do
        sign_in person(:club_manager).user
        post checklist_checklist_excuses_path(@checklist),
          params: { checklist_excuse: { item_id: @item.id, person_id: person(:member).id, event_id: @missed.id, reason: "Ill" } }
        assert_redirected_to checklist_path(@checklist)

        excuse = ChecklistExcuse.last
        assert_equal @missed, excuse.event
        assert_equal person(:club_manager), excuse.created_by
        assert_equal "met", evaluate(@checklist, :member, @item).status
        assert_equal "met", evaluate(@checklist, :member, nil).status
      end
    end
  end

  test "only the item's held meetings can be excused, and not by organizers or relatives" do
    elsewhere = Event.create!(name: "Not a meeting", event_type: event_types(:one), team: @club,
      start_time: Time.zone.parse("2026-10-06 18:00"), end_time: Time.zone.parse("2026-10-06 20:00"))
    Relationship.create!(parent: person(:club_manager), child: person(:member2), relationship_type: @parent_of, created_by: person(:admin))

    with_feature do
      travel_to Time.zone.parse("2026-10-10 12:00") do
        sign_in person(:club_manager).user
        post checklist_checklist_excuses_path(@checklist),
          params: { checklist_excuse: { item_id: @item.id, person_id: person(:member).id, event_id: elsewhere.id, reason: "Ill" } }
        assert_response :unprocessable_entity
        assert_match "Pick one of this item's meetings", response.body

        post checklist_checklist_excuses_path(@checklist),
          params: { checklist_excuse: { item_id: @item.id, person_id: person(:member2).id, event_id: @missed.id, reason: "Mine" } }
        assert_empty ChecklistExcuse.all, "nobody excuses a relative"

        sign_in person(:organizer).user
        post checklist_checklist_excuses_path(@checklist),
          params: { checklist_excuse: { item_id: @item.id, person_id: person(:member).id, event_id: @missed.id, reason: "Ill" } }
        assert_empty ChecklistExcuse.all, "organizers don't excuse"
      end
    end
  end

  test "the item form shows and saves the rules, and the report shows the results" do
    with_feature do
      travel_to Time.zone.parse("2026-10-10 12:00") do
        sign_in person(:club_manager).user
        get new_checklist_checklist_item_path(@checklist, kind: "attendance")
        assert_response :success
        assert_match "Rule 1: share of meeting hours (%)", response.body
        assert_match "Rule 4: counted together with", response.body

        post checklist_checklist_items_path(@checklist), params: { confirmed: "1", checklist_item: { kind: "attendance", label: "Meetings",
          config: { rule_1_name: "Summer", rule_1_starts_on: "2026-09-01", rule_1_ends_on: "2026-10-31", rule_1_share: "10",
            rule_1_with: "Late", rule_2_name: "Late", rule_2_starts_on: "2026-11-01", rule_2_share: "20", rule_2_weekly: "0",
            rule_2_judge_after: "2", extra_hours_count: "1", leeway_minutes: "2" } } }
        item = @checklist.checklist_items.find_by!(label: "Meetings")
        assert_equal({ "rule_1_name" => "Summer", "rule_1_starts_on" => "2026-09-01", "rule_1_ends_on" => "2026-10-31", "rule_1_share" => 10,
          "rule_1_with" => "Late", "rule_2_name" => "Late", "rule_2_starts_on" => "2026-11-01", "rule_2_share" => 20, "rule_2_weekly" => false,
          "rule_2_judge_after" => 2, "extra_hours_count" => true, "leeway_minutes" => 2 }, item.config)

        refresh(@checklist)
        get checklist_path(@checklist)
        assert_response :success
        assert_match "Below minimum", response.body
      end
    end
  end

  private

  def meeting(name, day)
    Event.create!(name: name, event_type: event_types(:one), team: @club, time_clock_period: @period,
      start_time: Time.zone.parse("#{day} 18:00"), end_time: Time.zone.parse("#{day} 20:00"))
  end
end
