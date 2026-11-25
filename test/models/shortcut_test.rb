require "test_helper"

class ShortcutTest < ActiveSupport::TestCase
  def shortcut(**attrs)
    Shortcut.new(name: "Attendance", icon: "list", team: teams(:one), target: "https://example.com/attendance", color: "#3788d8", **attrs)
  end

  test "accepts http(s) URLs and relative paths as targets" do
    [ "https://example.com/attendance", "http://example.com", "HTTPS://example.com", "/teams", "/teams?q=1#top" ].each do |target|
      assert shortcut(target: target).valid?, "expected #{target.inspect} to be a valid target"
    end
  end

  test "rejects targets that aren't http(s) URLs or relative paths" do
    [ nil, "", "javascript:alert(1)", " javascript:alert(1)", "JaVaScRiPt:alert(1)", "java\tscript:alert(1)",
      "data:text/html,<script>alert(1)</script>", "vbscript:x", "mailto:a@example.com", "//evil.example", "/\\evil.example", "/\t/evil.example", "/ teams",
      "https://", "teams", "MyString" ].each do |target|
      record = shortcut(target: target)
      assert_not record.valid?, "expected #{target.inspect} to be rejected"
      assert record.errors[:target].any?
    end
  end

  test "requires the color to be a hex color" do
    assert shortcut(color: "#A0b1C2").valid?
    [ nil, "", "red", "#fff", "#ff0000;position:fixed;inset:0", "#ff0000\n" ].each do |color|
      record = shortcut(color: color)
      assert_not record.valid?, "expected #{color.inspect} to be rejected"
      assert record.errors[:color].any?
    end
  end

  test "safe_target? checks stored values the same way" do
    record = shortcut
    record.target = "javascript:alert(1)"
    assert_not record.safe_target?
    record.target = "/teams"
    assert record.safe_target?
  end
end
