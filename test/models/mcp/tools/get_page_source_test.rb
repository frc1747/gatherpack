require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_page_world"

class Mcp::Tools::GetPageSourceTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld
  include McpPageWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_page_world
  end

  def source(viewer, page)
    call_tool("get_page_source", user: user(viewer), page_id: page.neat_id)
  end

  test "an admin gets any source, with the stored ERB unrun" do
    assert_equal({
      "id" => @pages[:dynamic].neat_id,
      "title" => "Dynamic",
      "viewer" => "admin",
      "editor" => "admin",
      "team" => nil,
      "dynamic" => true,
      "content" => "<%= 1 + 1 %>"
    }, source(:admin, @pages[:dynamic]).value)
  end

  test "a team manager gets the source of their team's pages" do
    assert_equal "the body of Alpha for team", source(:alpha_manager, @pages[:alpha_team]).value["content"]
    assert_equal({ "id" => @alpha.neat_id, "name" => "Alpha" }, source(:alpha_manager, @pages[:alpha_managers]).value["team"])
  end

  test "someone who can open a page but not edit it is not allowed" do
    assert_equal "Not allowed", source(:alpha_member, @pages[:alpha_team]).error
    assert_equal "Not allowed", source(:beta_member, @pages[:public]).error
    assert_equal "Not allowed", source(:guardian, @pages[:members]).error
    assert_equal "Not allowed", source(:alpha_manager, @pages[:members]).error
  end

  test "someone who can't open a page gets not found" do
    assert_equal "Not found", source(:beta_member, @pages[:alpha_team]).error
    assert_equal "Not found", source(:alpha_member, @pages[:alpha_managers]).error
    assert_equal "Not found", source(:guardian, @pages[:dynamic]).error
    assert_equal "Not found", source(:alpha_manager, @pages[:admin_only]).error
  end

  test "a team editor who's a plain member gets the source" do
    assert_equal "the body of Beta for team", source(:beta_member, @pages[:beta_team]).value["content"]
    assert_equal "Not found", source(:guardian, @pages[:beta_team]).error
  end

  test "it allows and refuses as the edit screen does" do
    %i[admin alpha_manager alpha_member beta_member guardian].product(@pages.keys).each do |viewer, key|
      sign_in user(viewer)
      get edit_page_path(@pages[key])
      sign_out user(viewer)

      assert_equal response.successful?, source(viewer, @pages[key]).error.nil?, "#{viewer} editing #{key}"
    end
  end

  test "invalid IDs are not found, and the feature being off refuses it" do
    [ "nonsense", @alpha.neat_id ].each { |bad| assert_equal "Not found", call_tool("get_page_source", user: user(:admin), page_id: bad).error }
    with_feature(:pages, false) { assert_equal "Feature off", source(:admin, @pages[:public]).error }
  end
end
