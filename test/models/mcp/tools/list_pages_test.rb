require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_page_world"

class Mcp::Tools::ListPagesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld
  include McpPageWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_page_world
    Page.where.not(id: @pages.values.map(&:id)).delete_all
  end

  def titles(viewer)
    call_tool("list_pages", user: user(viewer), limit: 100).value["items"].map { |item| item["title"] }
  end

  test "an admin lists every page" do
    assert_equal @pages.values.map(&:title).sort, titles(:admin).sort
  end

  test "a team manager lists what they can open" do
    assert_equal [ "Alpha for managers", "Alpha for team", "For members", "Public" ], titles(:alpha_manager)
  end

  test "a plain member on another team lists only open pages" do
    assert_equal [ "Beta for team", "For members", "Public" ], titles(:beta_member)
  end

  test "a guardian on no team lists only open pages" do
    assert_equal [ "For members", "Public" ], titles(:guardian)
  end

  test "a page on the viewer's team above their level is left out, as the index leaves it out" do
    sign_in user(:alpha_member)
    get pages_path
    assert_response :success
    assert_not_includes response.body, "Alpha for managers"

    assert_not_includes titles(:alpha_member), "Alpha for managers"
  end

  test "items carry the team and dynamic flag and no content" do
    result = call_tool("list_pages", user: user(:admin), limit: 100)
    item = result.value["items"].find { |candidate| candidate["title"] == "Dynamic" }

    assert_equal({ "id" => @pages[:dynamic].neat_id, "title" => "Dynamic", "team" => nil, "dynamic" => true }, item)
    assert_equal({ "id" => @alpha.neat_id, "name" => "Alpha" }, result.value["items"].find { |candidate| candidate["title"] == "Alpha for team" }["team"])
    assert_not_includes result.value.to_json, "the body of"
  end

  test "limit truncates only when there's more the viewer can open" do
    result = call_tool("list_pages", user: user(:guardian), limit: 1)
    assert_equal [ "For members" ], result.value["items"].map { |item| item["title"] }
    assert result.value["truncated"]

    assert_not call_tool("list_pages", user: user(:guardian), limit: 2).value["truncated"]
  end

  test "the feature being off refuses it" do
    with_feature(:pages, false) { assert_equal "Feature off", call_tool("list_pages", user: user(:admin)).error }
  end
end
