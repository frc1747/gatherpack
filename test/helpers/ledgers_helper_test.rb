require "test_helper"

class LedgersHelperTest < ActionView::TestCase
  include ApplicationHelper
  include FontAwesomeHelper

  NAME = "<img src=x onerror=alert(1)>"

  test "ledger_as_badge escapes the ledger name" do
    ledger = Ledger.create!(name: NAME, team: teams(:one))
    html = ledger_as_badge(ledger)

    assert_not html.include?(NAME), "ledger_as_badge emits the ledger name unescaped: #{html}"
    assert_includes html, "&lt;img src=x onerror=alert(1)&gt;"
    assert_includes html, %(<i class="fa-fw fa-solid fa-receipt"></i>)
    assert_equal html, as_badge(ledger)
  end

  test "ledger_tag_as_badge escapes the tag name" do
    html = ledger_tag_as_badge(LedgerTag.new(name: NAME, color: "#ffffff"))

    assert_not html.include?(NAME), "ledger_tag_as_badge emits the tag name unescaped: #{html}"
    assert_includes html, %(<i class="fa-fw fa-solid fa-stamp"></i>)
  end

  test "ledger_tag_as_badge doesn't put other CSS from the color into the style" do
    html = ledger_tag_as_badge(LedgerTag.new(name: "Travel", color: "#ff0000;position:fixed;inset:0"))

    assert_not html.include?("position:fixed"), "the tag color injects CSS: #{html}"
  end
end
