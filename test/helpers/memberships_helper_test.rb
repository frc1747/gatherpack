require "test_helper"

class MembershipsHelperTest < ActionView::TestCase
  include ApplicationHelper
  include FontAwesomeHelper

  test "membership_as_badge doesn't put other CSS from the team color into the style" do
    membership = memberships(:one)
    membership.team.color = "red;position:fixed;inset:0"

    html = membership_as_badge(membership)

    assert_not html.include?("position:fixed"), "the team color injects CSS: #{html}"
    assert_includes html, membership.team.name
  end
end
