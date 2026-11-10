require "test_helper"

class TeamsHelperTest < ActionView::TestCase
  include ApplicationHelper
  include FontAwesomeHelper

  test "team_as_badge uses the team color" do
    assert_includes team_as_badge(Team.new(name: "Alpha", color: "#3788d8", team_type: team_types(:one))), "background-color: #3788d8;"
  end

  test "team_as_badge doesn't put other CSS from the color into the style" do
    html = team_as_badge(Team.new(name: "Alpha", color: "red;position:fixed;inset:0", team_type: team_types(:one)))

    assert_not html.include?("position:fixed"), "the team color injects CSS: #{html}"
  end
end
