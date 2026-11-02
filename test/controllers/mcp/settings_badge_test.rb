require "test_helper"
require_relative "../../support/mcp_world"

# The MCP allowed-badge setting on the real settings page.
class Mcp::SettingsBadgeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  SELECT = "select[name='settings[mcp_allowed_badge]']".freeze

  setup do
    host! "localhost"
    build_mcp_world
    @other_badge = create_world_badge("Other Badge", team: @alpha)
    # Saves go through the settings controller; keep them out of the real store.
    @restore_badge_setting = apply_settings(mcp_allowed_badge: "")
  end

  teardown { @restore_badge_setting&.call }

  def save_badge(value)
    post update_settings_path, params: { settings: { mcp_allowed_badge: value } }
  end

  def connects?(person_name)
    mcp_post(mcp_token(user(person_name)), "tools/list")
    response.successful?
  end

  test "the select lists badges by name, blank first as Every member" do
    sign_in user(:admin)
    get settings_path

    assert_response :success
    assert_select "#{SELECT} option:first-child[value='']", "Every member"
    assert_select "#{SELECT} option[value='#{@access_badge.neat_id}']", "MCP Access"
    assert_select "#{SELECT} option[value='#{@other_badge.neat_id}']", "Other Badge"
    assert_select "#{SELECT} option[selected]", 1
    assert_select "#{SELECT} option[selected][value='']"
    assert_no_match(/bdg_\.\.\./, response.body)
    assert_no_match(/neat id/i, css_select("#{SELECT}").first.ancestors("div.row").text)
  end

  test "badges sharing a name show their team" do
    twin = create_world_badge("MCP Access", team: @beta)
    sign_in user(:admin)
    get settings_path

    assert_select "#{SELECT} option[value='#{twin.neat_id}']", "MCP Access (Beta)"
    assert_select "#{SELECT} option[value='#{@access_badge.neat_id}']", "MCP Access (no team)"
  end

  test "choosing a badge stores its neat ID and only holders connect" do
    sign_in user(:admin)
    save_badge(@access_badge.neat_id)

    assert_redirected_to settings_path
    assert_equal @access_badge.neat_id, Settings[:mcp_allowed_badge]
    assert connects?(:badge_holder)
    assert_not connects?(:alpha_member)
  end

  test "the stored badge shows as selected" do
    with_settings(mcp_allowed_badge: @access_badge.neat_id) do
      sign_in user(:admin)
      get settings_path

      assert_select "#{SELECT} option[selected]", 1
      assert_select "#{SELECT} option[selected][value='#{@access_badge.neat_id}']"
    end
  end

  test "blank means every member" do
    with_settings(mcp_allowed_badge: @access_badge.neat_id) do
      sign_in user(:admin)
      save_badge("")

      assert_equal "", Settings[:mcp_allowed_badge]
      assert connects?(:alpha_member)
    end
  end

  test "a missing badge shows an explicit selected option and saving keeps it locked" do
    with_settings(mcp_allowed_badge: "bdg_gone") do
      sign_in user(:admin)
      get settings_path

      assert_select "#{SELECT} option[selected]", 1
      assert_select "#{SELECT} option[selected][value='bdg_gone']", "Missing badge (no one can connect)"
      assert_select "#{SELECT} option[selected][value='']", 0

      save_badge("bdg_gone")

      assert_equal "bdg_gone", Settings[:mcp_allowed_badge]
      assert_not connects?(:alpha_member)
      assert_not connects?(:badge_holder)
    end
  end

  test "a deleted badge shows as missing" do
    with_settings(mcp_allowed_badge: @other_badge.neat_id) do
      neat_id = @other_badge.neat_id
      @other_badge.destroy!
      sign_in user(:admin)
      get settings_path

      assert_select "#{SELECT} option[selected][value='#{neat_id}']", "Missing badge (no one can connect)"
    end
  end

  test "a non-admin can't reach or change it" do
    sign_in user(:alpha_manager)

    get settings_path
    assert_redirected_to root_path

    save_badge(@access_badge.neat_id)
    assert_redirected_to root_path
    assert_equal "", Settings[:mcp_allowed_badge]
  end

  test "with the feature off the setting is still on the page" do
    with_feature(:mcp, false) do
      sign_in user(:admin)
      get settings_path

      assert_response :success
      assert_select SELECT
    end
  end
end
