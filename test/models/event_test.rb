require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup do
    @org = Team.create!(name: "Org", team_type: team_types(:one))
    @team_a = Team.create!(name: "Team A", team_type: team_types(:one), parent: @org)
    @team_b = Team.create!(name: "Team B", team_type: team_types(:one), parent: @org)
    @event = Event.new(name: "A practice", start_time: 1.day.from_now, event_type: event_types(:one), team: @team_a)
  end

  test "the fixtures are valid" do
    assert events(:one).valid?
    assert events(:two).valid?
  end

  test "an event can count toward a time clock period of its own team" do
    @event.time_clock_period = create_period(@team_a)
    assert @event.valid?
  end

  test "an event can count toward a time clock period of a team above its own" do
    @event.time_clock_period = create_period(@org)
    assert @event.valid?
  end

  test "an event can count toward a time clock period with no team" do
    @event.time_clock_period = create_period(nil)
    assert @event.valid?
  end

  test "an event can't count toward another team's time clock period" do
    @event.time_clock_period = create_period(@team_b)

    assert_not @event.valid?
    assert_includes @event.errors[:time_clock_period_id], "must belong to the event's team or a team above it"
  end

  test "an event with no team can't count toward a team's time clock period" do
    @event.team = nil
    @event.time_clock_period = create_period(@team_a)

    assert_not @event.valid?
  end

  test "moving an event out of its period's team makes it invalid" do
    @event.update!(time_clock_period: create_period(@team_a))
    @event.team = @team_b

    assert_not @event.valid?
  end

  test "an event can't count toward a time clock period that doesn't exist" do
    @event.time_clock_period_id = SecureRandom.uuid

    assert_not @event.valid?
    assert_includes @event.errors[:time_clock_period_id], "doesn't exist"
  end

  private

  def create_period(team)
    TimeClockPeriod.create!(name: "Season", team: team, start_time: 1.month.ago, end_time: 1.month.from_now)
  end
end
