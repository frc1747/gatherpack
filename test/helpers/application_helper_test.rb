require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "contrasting_color picks text color by brightness" do
    assert_equal "#000", contrasting_color("#ffffff")
    assert_equal "#fff", contrasting_color("#000000")
    assert_equal "#6d6753", contrasting_color("#34c233", dark: "#6d6753", light: "#fffdf6")
  end

  test "contrasting_color falls back instead of raising on blank or non-hex colors" do
    [ nil, "", "  ", "red", "#zzz" ].each do |color|
      assert_equal "#000", contrasting_color(color), "for #{color.inspect}"
    end
  end

  test "event_calendar_colors uses the team color" do
    colors = event_calendar_colors(Event.new(team: Team.new(color: "#000000")))
    assert_equal({ background: "#000000", text: "#fffdf6" }, colors)
  end

  test "event_calendar_colors falls back to the default for missing or invalid colors" do
    [ Event.new, Event.new(team: Team.new(color: nil)), Event.new(team: Team.new(color: "red")) ].each do |event|
      assert_equal ApplicationHelper::DEFAULT_EVENT_COLOR, event_calendar_colors(event)[:background]
    end
  end

  test "flash_to_class maps notice to info and alert to danger" do
    assert_equal "alert-info", flash_to_class("notice")
    assert_equal "alert-danger", flash_to_class("alert")
  end

  test "flash_to_class passes other keys through" do
    assert_equal "alert-warning", flash_to_class("warning")
    assert_equal "alert-success", flash_to_class("success")
  end

  test "flash_to_icon gives alert the same icon as danger" do
    assert_equal "fa-triangle-exclamation", flash_to_icon("danger")
    assert_equal "fa-triangle-exclamation", flash_to_icon("alert")
    assert_equal "fa-circle-info", flash_to_icon("notice")
  end
end
