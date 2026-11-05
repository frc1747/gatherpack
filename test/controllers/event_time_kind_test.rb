require "test_helper"

class EventTimeKindDisplayTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    @admin = admin
    sign_in admin
    @day = 3.days.from_now.in_time_zone(zone).to_date
  end

  test "the form offers the three choices" do
    get new_event_path

    assert_response :success
    assert_select "[data-controller='event-time']" do
      assert_select "input[type=radio][name='event[time_kind]']", 3
      assert_select "label", text: "At a set time"
      assert_select "label", text: "All day"
      assert_select "label", text: "Time to be announced"
      assert_select "[data-event-time-target=timeField] input[name='event[start_time]']"
      assert_select "[data-event-time-target=timeField] input[name='event[end_time]']"
      assert_select "[data-event-time-target=dateField] input[type=date][name='event[event_date]']"
    end
  end

  test "the form saves a chosen kind and ignores the time fields" do
    post events_path, params: { event: event_params(time_kind: "tba", event_date: "2026-11-21", start_time: "2026-11-07T14:00", end_time: "2026-11-07T16:00") }

    event = Event.find_by!(name: "Open house")
    assert_redirected_to event
    assert_predicate event, :tba?
    assert_equal "2026-11-21", event.start_time.in_time_zone(zone).to_date.iso8601
  end

  test "the form can return an event to a set time" do
    event = create_event(:tba)

    patch event_path(event), params: { event: { time_kind: "timed", start_time: "2026-11-07T14:00", end_time: "2026-11-07T16:00" } }

    assert_redirected_to event
    event.reload
    assert_predicate event, :timed?
    assert_equal 2.0, event.hours
  end

  test "a day is required when the time isn't set" do
    post events_path, params: { event: event_params(time_kind: "all_day", event_date: "", start_time: "") }

    assert_response :unprocessable_entity
    assert_select "[data-event-time-target=dateField] .invalid-feedback"
  end

  test "show gives the date only for an all-day event" do
    get event_path(create_event(:all_day))

    assert_response :success
    assert_select ".card-body p", text: @day.to_fs(:long_ordinal)
  end

  test "show gives the date and Time TBA for a TBA event" do
    get event_path(create_event(:tba))

    assert_select ".card-body p", text: "#{@day.to_fs(:long_ordinal)} - Time TBA"
  end

  test "show still gives the times for a timed event" do
    event = create_event(:timed)

    get event_path(event)

    assert_select ".card-body p", text: "#{event.start_time.in_time_zone(zone).to_fs(:long_ordinal)} - #{event.end_time.in_time_zone(zone).to_fs(:long_ordinal)}"
  end

  test "index shows what is known of each kind" do
    all_day = create_event(:all_day)
    tba = create_event(:tba)
    timed = create_event(:timed)

    get events_path

    assert_response :success
    assert_select "##{dom_id_for(all_day)} .card-body", text: @day.to_fs(:short)
    assert_select "##{dom_id_for(tba)} .card-body", text: "#{@day.to_fs(:short)} - Time TBA"
    assert_select "##{dom_id_for(timed)} .card-body", text: /\d\d:\d\d - /
  end

  test "index adds the location after what is known" do
    tba = create_event(:tba, location: "Gym")

    get events_path

    assert_select "##{dom_id_for(tba)} .card-body", text: "#{@day.to_fs(:short)} - Time TBA at Gym"
  end

  test "an event badge shows what is known of each kind" do
    all_day = create_event(:all_day, name: "Fair")
    tba = create_event(:tba, name: "Game")
    timed = create_event(:timed, name: "Practice")

    assert_includes badge_for(all_day), "Fair (#{@day.iso8601})"
    assert_includes badge_for(tba), "Game (#{@day.iso8601}, Time TBA)"
    assert_includes badge_for(timed), "Practice (#{timed.start_time.in_time_zone(zone)})"
  end

  test "calendar JSON draws all-day and TBA events as all-day" do
    all_day = create_event(:all_day, name: "Fair")
    tba = create_event(:tba, name: "Game")
    timed = create_event(:timed, name: "Practice")

    get "/calendar/calendar.json", params: { events: "1", start_time: (@day - 1).iso8601, end_time: (@day + 1).iso8601 }

    assert_response :success
    entries = response.parsed_body.index_by { |entry| entry["id"] }
    assert_equal [ "Fair", true, @day.iso8601, nil ], entries[all_day.id].values_at("title", "allDay", "start", "end")
    assert_equal [ "Game (TBA)", true, @day.iso8601, nil ], entries[tba.id].values_at("title", "allDay", "start", "end")
    assert_equal [ "Practice", false ], entries[timed.id].values_at("title", "allDay")
    assert_predicate entries[timed.id]["end"], :present?
  end

  test "the team calendar draws all-day and TBA events as all-day" do
    all_day = create_event(:all_day, name: "Fair")
    tba = create_event(:tba, name: "Game")
    timed = create_event(:timed, name: "Practice")
    Membership.create!(person: @admin.person, team: @team)

    get team_path(@team)

    assert_response :success
    inline = JSON.parse(css_select("[data-calendar-inline-events-value]").first["data-calendar-inline-events-value"]).index_by { |entry| entry["id"] }
    assert_equal [ "Fair", true, @day.iso8601, nil ], inline[all_day.id].values_at("title", "allDay", "start", "end")
    assert_equal [ "Game (TBA)", true, @day.iso8601, nil ], inline[tba.id].values_at("title", "allDay", "start", "end")
    assert_equal [ "Practice", false ], inline[timed.id].values_at("title", "allDay")
  end

  test "the public team page shows what is known of each kind" do
    create_event(:all_day, name: "Fair")
    create_event(:tba, name: "Game")
    view_as_outsider

    get team_path(@team)

    assert_response :success
    rows = css_select(".d-flex.justify-content-between").to_h { |row| [ row.at_css("a").text, row.at_css("small").text ] }
    assert_equal @day.strftime("%B %-d, %Y"), rows["Fair"]
    assert_equal "#{@day.strftime("%B %-d, %Y")} - Time TBA", rows["Game"]
  end

  test "the public team page keeps listing an all-day event on its day" do
    @day = Time.current.in_time_zone(zone).to_date
    create_event(:all_day, name: "Fair")
    view_as_outsider

    get team_path(@team)

    assert_select ".d-flex.justify-content-between a", text: "Fair"
  end

  private

  def zone
    Settings[:time_zone].presence || "UTC"
  end

  def badge_for(event)
    Time.use_zone(zone) { ApplicationController.render(inline: "<%= as_badge(event) %>", locals: { event: Event.find(event.id) }) }
  end

  def dom_id_for(event)
    ActionView::RecordIdentifier.dom_id(event)
  end

  def view_as_outsider
    @team.update!(join_permission: "has_account")
    outsider = User.create!(email: "outsider@example.com", password: "Password1!")
    Person.create!(user: outsider, first_name: "Out", last_name: "Sider")
    sign_out @admin
    sign_in outsider
  end

  def event_params(**attributes)
    { name: "Open house", event_type_id: event_types(:one).id, team_id: @team.id }.merge(attributes)
  end

  def create_event(kind, **attributes)
    Time.use_zone(zone) do
      start_time = @day.in_time_zone.change(hour: 14)
      Event.create!(name: "Meet", event_type: event_types(:one), team: @team, time_kind: kind,
        start_time: start_time, end_time: start_time + 2.hours, **attributes)
    end
  end
end
