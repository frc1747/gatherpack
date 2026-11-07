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
    @item = add_item(@checklist, :attendance, "Attendance", { rules: [ { name: "Fall", share: "60" } ] })
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
    with_feature do
      travel_to Time.zone.parse("2026-10-10 12:00") do
        give_badge(:member, @safety)
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
        TimeClockPeriod.create!(name: "Other Org season", team: @other_org, start_time: Date.new(2026, 9, 1),
          end_time: Date.new(2027, 6, 30), permission: :added_by_admin)
        get new_checklist_checklist_item_path(@checklist, kind: "attendance")
        assert_response :success
        assert_select "#attendance-rules tbody tr", 1, "one blank row to start"
        assert_select "template[data-attendance-rules-target=template]"
        assert_match "Judged on its own", response.body
        assert_select "#attendance_period_ids option", text: /Season/
        assert_select "#attendance_period_ids option", text: /Other Org season/, count: 0

        post checklist_checklist_items_path(@checklist), params: { confirmed: "1", checklist_item: { kind: "attendance", label: "Meetings",
          config: { extra_hours_count: "1", leeway_minutes: "2", period_ids: [ "", @period.id ], rules: {
            "0" => { name: "Summer", starts: { mode: "date", date: "2026-09-01" }, ends_on: "2026-10-31", share: "10", with: "Late", weekly: "0" },
            "1" => { name: "Late", starts: { mode: "within", amount: "2", unit: "months" }, ends_on: "", share: "20", weekly: "0", judge_after: "2" },
            "1700000000000" => { name: "", starts: { mode: "" }, ends_on: "", share: "", weekly: "0", judge_after: "" } } } } }
        item = @checklist.checklist_items.find_by!(label: "Meetings")
        assert_equal({ "extra_hours_count" => true, "leeway_minutes" => 2, "period_ids" => [ @period.id ], "rules" => [
          { "name" => "Summer", "starts" => { "mode" => "date", "date" => "2026-09-01" }, "ends_on" => "2026-10-31", "share" => 10,
            "weekly" => false, "with" => "Late", "judge_after" => 0 },
          { "name" => "Late", "starts" => { "mode" => "within", "amount" => 2, "unit" => "months" }, "ends_on" => nil, "share" => 20,
            "weekly" => false, "with" => nil, "judge_after" => 2 }
        ] }, item.config)

        get edit_checklist_checklist_item_path(@checklist, item)
        assert_select "#attendance-rules tbody tr", 3, "the two rules and a blank row"
        assert_select "#attendance-rules input[value=Summer]"

        patch checklist_checklist_item_path(@checklist, item), params: { confirmed: "1", checklist_item: { config: { rules: {
          "0" => { name: "Fall", starts: { mode: "within", amount: "", unit: "months" }, share: "30" } } } } }
        assert_response :unprocessable_entity
        assert_match "Fall: say how many days or months", response.body
        assert_select "#attendance-rules tbody tr:first-child select[aria-label='Rule starts'] option[selected][value=within]"
        assert_equal "Summer", item.reload.config["rules"].first["name"], "nothing saved"

        refresh(@checklist)
        get checklist_path(@checklist)
        assert_response :success
        assert_match "Below minimum", response.body
      end
    end
  end

  test "an expired meeting excuse is shown as expired and the meeting can be excused again" do
    ChecklistExcuse.create!(item: @item, person: person(:member), event: @missed, reason: "Ill", created_by: person(:club_manager),
      expires_on: Date.new(2026, 10, 8))

    with_feature do
      travel_to Time.zone.parse("2026-10-10 12:00") do
        sign_in person(:club_manager).user
        get new_checklist_checklist_excuse_path(@checklist, item_id: @item.id, person_id: person(:member).id)
        assert_response :success
        assert_match "Expired October 08, 2026", response.body
        assert_select "option[value=?]", @missed.id

        post checklist_checklist_excuses_path(@checklist),
          params: { checklist_excuse: { item_id: @item.id, person_id: person(:member).id, event_id: @missed.id, reason: "Ill again" } }
        assert_redirected_to checklist_path(@checklist)
        assert_equal 2, ChecklistExcuse.where(event: @missed).count
      end
    end
  end

  private

  def meeting(name, day)
    Event.create!(name: name, event_type: event_types(:one), team: @club, time_clock_period: @period,
      start_time: Time.zone.parse("#{day} 18:00"), end_time: Time.zone.parse("#{day} 20:00"))
  end
end
