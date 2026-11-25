require "test_helper"

class AnnouncementTest < ActiveSupport::TestCase
  def search(term)
    Announcement.ransack(name_or_content_i_cont: term).result # what site search asks for
  end

  def announcement(title:, content:)
    Announcement.create!(title: title, content: content, start_time: 1.day.ago, end_time: 1.day.from_now)
  end

  test "search matches the title" do
    found = announcement(title: "Concessions sign-up", content: "Sign up on the sheet.")
    assert_includes search("concessions"), found
  end

  test "search matches visible text" do
    found = announcement(title: "Meeting", content: "<p>Bring <strong>Concessions</strong> money</p>")
    assert_includes search("concessions"), found
  end

  test "search matches the text of a link but not its target" do
    found = announcement(title: "Links", content: "See [the schedule](https://example.com/zebra) or <a href=\"https://example.com/zebra\">the plan</a>")
    assert_includes search("schedule"), found
    assert_includes search("the plan"), found
    assert_not_includes search("zebra"), found
  end

  test "search does not match words only in HTML attributes" do
    found = announcement(title: "Photo", content: "<img src=\"/uploads/zebra.png\" alt=\"team\"> <span class=\"zebra\">Hello</span>")
    assert_not_includes search("zebra"), found
    assert_includes search("hello"), found
  end
end
