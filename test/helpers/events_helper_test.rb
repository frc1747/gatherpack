require "test_helper"

class EventsHelperTest < ActionView::TestCase
  include ApplicationHelper
  include FontAwesomeHelper

  setup do
    @event = events(:one)
    @event.team = teams(:one)
  end

  test "event_as_badge uses the team color, or the default without a team" do
    @event.team.color = "#3788d8"
    assert_includes event_as_badge(@event), "background-color: #3788d8;"

    @event.team = nil
    assert_includes event_as_badge(@event), "background-color: #0dcaf0;"
  end

  test "event_as_badge doesn't put other CSS from the team color into the style" do
    @event.team.color = "red;position:fixed;inset:0"

    html = event_as_badge(@event)

    assert_not html.include?("position:fixed"), "the team color injects CSS: #{html}"
    assert_includes html, "background-color: #0dcaf0;"
  end
end
