require "test_helper"

class BadgesHelperTest < ActionView::TestCase
  include ApplicationHelper
  include FontAwesomeHelper

  test "badge_as_badge uses the badge color" do
    badge = badges(:one)
    badge.color = "#3788d8"

    assert_includes badge_as_badge(badge), "background-color: #3788d8;"
  end

  test "badge_as_badge doesn't put other CSS from the color into the style" do
    badge = badges(:one)
    badge.color = "#ff0000;position:fixed;inset:0"

    html = badge_as_badge(badge)

    assert_not html.include?("position:fixed"), "the badge color injects CSS: #{html}"
  end
end
