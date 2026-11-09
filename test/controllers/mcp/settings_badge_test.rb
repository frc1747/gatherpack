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
    @restore_badge_setting = apply_settings(mcp_allowed_badge: "", mcp_write_enabled: "false")
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
    assert_select "#{SELECT} option[value='#{@access_badge.neat_id}']", "MCP Access (no team)"
    assert_select "#{SELECT} option[value='#{@other_badge.neat_id}']", "Other Badge (Alpha)"
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

  # Writes the store directly, as a save through another web worker does: this
  # process's cached value stays as it was.
  def write_behind_cache(key, value)
    store = Settings.instance.store
    store.transaction { store[key] = value }
  end

  test "the select has the app's select styling" do
    sign_in user(:admin)
    get settings_path

    assert_select "select.form-select[name='settings[mcp_allowed_badge]']"
    assert_select "select.form-control[name='settings[mcp_allowed_badge]']", 0
  end

  test "badges can't pass for the special options" do
    fake_blank = create_world_badge("every  Member ", team: @beta)
    fake_missing = create_world_badge("Missing badge (no one can connect)")
    sign_in user(:admin)
    get settings_path

    assert_select "#{SELECT} option[value='']", 1
    assert_select "#{SELECT} option[value='#{fake_blank.neat_id}']", "every Member (Beta)"
    assert_select "#{SELECT} option[value='#{fake_missing.neat_id}']", "Missing badge (no one can connect) (no team)"
  end

  test "a badge named like the missing option doesn't hide a real missing badge" do
    fake = create_world_badge("Missing badge (no one can connect)")
    with_settings(mcp_allowed_badge: "bdg_gone") do
      sign_in user(:admin)
      get settings_path

      assert_select "#{SELECT} option[selected]", 1
      assert_select "#{SELECT} option[selected][value='bdg_gone']", "Missing badge (no one can connect)"
      assert_select "#{SELECT} option[value='#{fake.neat_id}']", "Missing badge (no one can connect) (no team)"
    end
  end

  test "badges that still read alike get more detail" do
    a = create_world_badge("Same", team: @beta)
    b = create_world_badge("Same", team: @beta)
    b.update!(short: "Two")
    c = create_world_badge("Same", team: @beta)
    c.update!(short: b.short)
    sign_in user(:admin)
    get settings_path

    labels = css_select("#{SELECT} option").map(&:text)
    assert_equal labels.uniq, labels
    assert_select "#{SELECT} option[value='#{a.neat_id}']", /\ASame \(Beta\) \(Sam\)\z/
    assert_select "#{SELECT} option[value='#{c.neat_id}']", /Same \(Beta\) \(Two\) \(bdg_/
  end

  test "badge and team names are escaped" do
    team = create_world_team("<img src=x onerror=alert(2)>")
    create_world_badge("<script>alert(1)</script>", team: team)
    create_world_badge("<script>alert(1)</script>")
    sign_in user(:admin)
    get settings_path

    assert_no_match(/<script>alert\(1\)/, response.body)
    assert_no_match(/<img src=x/, response.body)
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt; (&lt;img src=x onerror=alert(2)&gt;)"
  end

  test "a padded stored value shows its badge as selected" do
    with_settings(mcp_allowed_badge: "  #{@access_badge.neat_id} ") do
      sign_in user(:admin)
      get settings_path

      assert_select "#{SELECT} option[selected][value='#{@access_badge.neat_id}']"
      assert_select "#{SELECT} option", text: /Missing badge/, count: 0
    end
  end

  test "badges members can give themselves aren't offered" do
    self_service = %i[added_by_current_member added_by_manager_or_self added_by_admin_or_self has_account].map do |permission|
      create_world_badge("Free #{permission}", team: @alpha).tap { |badge| badge.update_columns(permission: Badge.permissions.fetch(permission)) }
    end
    sign_in user(:admin)
    get settings_path

    self_service.each { |badge| assert_select "#{SELECT} option[value='#{badge.neat_id}']", 0 }
    assert_select "#{SELECT} option[value='#{@other_badge.neat_id}']"
  end

  test "a stored self-service badge stays selected and is labelled" do
    free = create_world_badge("Free", team: @alpha)
    free.update_columns(permission: Badge.permissions.fetch(:added_by_manager_or_self))
    with_settings(mcp_allowed_badge: free.neat_id) do
      sign_in user(:admin)
      get settings_path

      assert_select "#{SELECT} option[selected]", 1
      assert_select "#{SELECT} option[selected][value='#{free.neat_id}']", "Free (Alpha) (members can give this to themselves)"
    end
  end

  test "a limit saved through another worker applies here" do
    write_behind_cache(:mcp_allowed_badge, @access_badge.neat_id)

    assert connects?(:badge_holder)
    assert_not connects?(:alpha_member)
  end

  test "the page shows the saved value, not this worker's copy" do
    write_behind_cache(:mcp_allowed_badge, @access_badge.neat_id)
    sign_in user(:admin)
    get settings_path

    assert_select "#{SELECT} option[selected]", 1
    assert_select "#{SELECT} option[selected][value='#{@access_badge.neat_id}']"
  end

  test "write and feature switches saved through another worker apply here" do
    write_behind_cache(:mcp_write_enabled, "true")
    assert Mcp::Access.writes_enabled?

    write_behind_cache(:mcp_dynamic_pages_enabled, "true")
    assert Mcp::Access.dynamic_pages_enabled?

    write_behind_cache(:feature_mcp, "false")
    assert_not Mcp::Access.enabled?
  end

  test "a badge name with invisible characters can't pass for Every member" do
    fake = create_world_badge("Every\u200B member")
    sign_in user(:admin)
    get settings_path

    labels = css_select("#{SELECT} option").map(&:text)
    assert_equal labels.uniq, labels
    assert_select "#{SELECT} option[value='']", "Every member"
    assert_select "#{SELECT} option[value='#{fake.neat_id}']", "Every\u200B member (no team)"
  end

  test "a self-service note can't make two labels read alike" do
    free = create_world_badge("Free", team: @alpha)
    free.update_columns(permission: Badge.permissions.fetch(:added_by_manager_or_self))
    create_world_badge("Free (Alpha) (members can give this to themselves)", team: @alpha)
    with_settings(mcp_allowed_badge: free.neat_id) do
      sign_in user(:admin)
      get settings_path

      labels = css_select("#{SELECT} option").map(&:text)
      assert_equal labels.uniq, labels
    end
  end

  test "reading while another thread saves raises nothing" do
    errors = Queue.new
    readers = Array.new(5) do
      Thread.new do
        50.times do
          Mcp::Access.enabled?
          Mcp::Access.writes_enabled?
          Mcp::Access.stored_setting(:mcp_allowed_badge)
        end
      rescue => e
        errors << e
      end
    end
    writer = Thread.new do
      20.times { |i| Settings[:mcp_allowed_badge] = (i.even? ? @access_badge.neat_id : "") }
    rescue => e
      errors << e
    end
    (readers + [ writer ]).each(&:join)

    assert_empty Array.new(errors.size) { errors.pop }
  end

  test "the settings page refreshes MCP's settings from the store" do
    write_behind_cache(:feature_mcp, "false")
    write_behind_cache(:feature_oauth_provider, "false")
    write_behind_cache(:mcp_write_enabled, "true")
    sign_in user(:admin)
    get settings_path

    assert_select "select[name='settings[feature_mcp]'] option[selected][value='false']"
    assert_select "select[name='settings[mcp_write_enabled]'] option[selected][value='true']"
    assert_select "select[name='settings[feature_oauth_provider]'] option[selected][value='false']"
  end

  test "a full-form save from a stale worker doesn't turn MCP back on" do
    Settings[:feature_mcp] = "true"
    write_behind_cache(:feature_mcp, "false")
    sign_in user(:admin)
    get settings_path
    form = css_select("select[name^='settings[feature_mcp'], select[name^='settings[mcp_write'], select[name^='settings[feature_oauth']").to_h do |select|
      [ select["name"][/\[(.+)\]/, 1], select.at_css("option[selected]")["value"] ]
    end
    post update_settings_path, params: { settings: form }

    assert_equal "false", Mcp::Access.stored_setting(:feature_mcp)
    assert_not Mcp::Access.enabled?
  end

  test "oauth_provider switched off through another worker applies here" do
    write_behind_cache(:feature_oauth_provider, "false")

    assert_not Mcp::Access.enabled?
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
