require "test_helper"
require "my_gatherpack_test_helper"

class MyGatherpackHelperTest < ActionView::TestCase
  include MyGatherpackTestHelper

  ORIGINAL_TITLE = "<title> <%= Settings[:title] %> | <%= content_for(:title) %></title>".freeze
  HELPER_TITLE = "<title><%= browser_title %></title>".freeze

  setup { turn_on_my_gatherpack(title: "Tom & Jerry") }
  teardown { restore_my_gatherpack }

  test "with the flag on, a page with no title shows the site alone" do
    assert_equal "<title>Tom &amp; Jerry</title>", view.render(inline: HELPER_TITLE)
  end

  test "with the flag on, a blank page title counts as no title" do
    view.content_for(:title, "")

    assert_equal "<title>Tom &amp; Jerry</title>", view.render(inline: HELPER_TITLE)
  end

  test "with the flag on, a page title follows the site's" do
    view.content_for(:title, "Events & Things")

    assert_equal "<title>Tom &amp; Jerry | Events &amp; Things</title>", view.render(inline: HELPER_TITLE)
  end

  test "with the flag on, a blank site title falls back in both forms" do
    Settings[:title] = ""
    assert_equal "<title>GatherPack</title>", view.render(inline: HELPER_TITLE)

    view.content_for(:title, "Events")
    assert_equal "<title>GatherPack | Events</title>", view.render(inline: HELPER_TITLE)
  end

  test "with the flag off, the output is the original template's" do
    Settings[:feature_my_gatherpack] = "false"

    [ "Tom & Jerry", "" ].each do |site|
      Settings[:title] = site
      assert_equal view.render(inline: ORIGINAL_TITLE), view.render(inline: HELPER_TITLE)
    end

    view.content_for(:title, "Events & Things")
    assert_equal view.render(inline: ORIGINAL_TITLE), view.render(inline: HELPER_TITLE)
    assert_includes view.render(inline: HELPER_TITLE), "Events &amp; Things"
  end
end
