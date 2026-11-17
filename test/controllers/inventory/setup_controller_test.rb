require "test_helper"
require "support/inventory_world"

class Inventory::SetupControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
  end

  test "an admin sees the settings with their current values" do
    with_inventory(@world, inventory_users: "#{@world.club.name}\n#{@world.art.name}", inventory_reorder_notice: "each") do
      sign_in @world.admin.user
      get inventory_setup_path
      assert_response :success
      assert_select "h1", text: "Inventory setup"
      assert_includes response.body, "Who Can Use Inventory"
      assert_includes response.body, "Inventory Managers"
      assert_includes response.body, "Running Low Notices"
      assert_includes response.body, "Undo Minutes"
      if Settings.respond_to?(:input)
        assert_select "option[selected]", text: "An email each time"
        assert_select "input[type=checkbox][checked][value=?]", @world.club.name
        assert_select "input[type=checkbox][checked][value=?]", @world.art.name
        assert_select "input[type=checkbox][checked][value=?]", @world.outreach.name, count: 0
      else
        assert_select "option[selected][value=each]"
        assert_select "textarea", text: /#{@world.club.name}\s+#{@world.art.name}/
      end
    end
  end

  test "a notice setting that isn't one of the three words isn't changed by opening and saving" do
    skip "plain page only" if Settings.respond_to?(:input)
    with_inventory(@world, inventory_reorder_notice: "Daily") do
      sign_in @world.admin.user
      get inventory_setup_path
      assert_select "option[selected][value=daily]"
    end
  end

  test "saving keeps the text as it was" do
    original = { inventory_users: "Alpha\r\nBeta", inventory_managers: "Keeper > Club", inventory_reorder_notice: "daily" }
    with_inventory(@world, **original) do
      sign_in @world.admin.user
      get inventory_setup_path
      assert_response :success
      form = css_select("form[action='#{update_settings_path}'], form[action='#{inventory_setup_path}']").first
      assert form
      if Settings.respond_to?(:input)
        # What the pickers post for the saved values (SettingInput).
        post update_settings_path, params: { return_to: inventory_setup_path, settings: {
          inventory_users: { values: [ "", "Alpha", "Beta" ] },
          inventory_managers: { rows: { "0" => { line: "Keeper > Club" } } },
          inventory_reorder_notice: "daily"
        } }
        assert_redirected_to inventory_setup_path
      else
        patch inventory_setup_path, params: { settings: original }
      end
      assert_response :see_other unless Settings.respond_to?(:input)
      original.each { |key, text| assert_equal text, Settings[key] }
      assert_equal Inventory::Config::DEFAULT_UNDO_MINUTES.to_s, Settings[:inventory_undo_minutes]
    end
  end

  test "update saves the settings posted and leaves the others" do
    with_inventory(@world) do
      sign_in @world.admin.user
      patch inventory_setup_path, params: { settings: { inventory_reorder_notice: "off", inventory_users: "Club", inventory_undo_minutes: "99" } }
      assert_redirected_to inventory_setup_path
      assert_equal "off", Settings[:inventory_reorder_notice]
      assert_equal "Club", Settings[:inventory_users]
      assert_equal "99", Settings[:inventory_undo_minutes]
      assert_not_equal "Pair", Settings[:inventory_default_unit]
    end
  end

  test "every inventory setting is on the setup page" do
    registered = Settings.settings("Inventory").map(&:setting_key)
    assert_empty registered - Inventory::SetupController::KEYS, "list these in Inventory::SetupController::GROUPS"
    assert_empty Inventory::SetupController::KEYS - registered
    with_inventory(@world) do
      sign_in @world.admin.user
      get inventory_setup_path
      assert_response :success
      registered.each do |key|
        assert_includes response.body, Settings.get(key).name, "#{key} is missing from Inventory setup"
      end
    end
  end

  test "every inventory setting saves from the setup page" do
    skip "plain page only" if Settings.respond_to?(:input)
    values = { inventory_users: "Club", inventory_managers: "Keeper > Club", inventory_member_kinds: "used, moved",
      inventory_member_unit_actions: "install, move", inventory_used_needs_reason: "true", inventory_undo_minutes: "25",
      inventory_reorder_notice: "weekly" }
    assert_equal Inventory::SetupController::KEYS.sort, values.keys.sort
    with_inventory(@world) do
      sign_in @world.admin.user
      patch inventory_setup_path, params: { settings: values }
      assert_redirected_to inventory_setup_path
      values.each { |key, value| assert_equal value, Settings[key].to_s.gsub("\r\n", "\n"), key }
    end
  end

  test "the page works without JavaScript: plain fields, one form, a Save button" do
    skip "plain page only" if Settings.respond_to?(:input)
    with_inventory(@world) do
      sign_in @world.admin.user
      get inventory_setup_path
      assert_select "form[action=?]", inventory_setup_path, count: 1
      assert_select "input[type=submit][value=Save]"
      Inventory::SetupController::KEYS.each { |key| assert_select "[name=?]", "settings[#{key}]" }
    end
  end

  test "the managers picker says a blank team means every team" do
    skip "needs the settings seam" unless Settings.respond_to?(:input)
    assert_equal "Up to: every team", Settings.input_for(:inventory_managers).options[:blank_team_label]
    with_inventory(@world) do
      sign_in @world.admin.user
      get inventory_setup_path
      assert_select "select[name$='[team]'] option[value='']", text: "Up to: every team"
    end
  end

  test "only admins open or save the page" do
    with_inventory(@world) do
      [ @world.manager, @world.keeper, @world.member ].each do |person|
        sign_in person.user
        get inventory_setup_path
        assert_redirected_to root_path
        patch inventory_setup_path, params: { settings: { inventory_users: "Nobody" } }
        assert_redirected_to root_path
        assert_not_equal "Nobody", Settings[:inventory_users]
        sign_out person.user
      end
    end
  end

  test "Inventory setup is a button on the main Setup page for admins, not a menu item" do
    with_inventory(@world) do
      sign_in @world.admin.user
      get setup_path
      assert_select "a.btn[href=?]", inventory_setup_path, text: "Inventory"
      assert_select "h6, h5, h4, h3, h2", text: "Orders and Inventory"
      %i[location_types stock_units unit_conditions reading_types].each do |key|
        assert_select "a[href=?]", managed_list_path(key)
      end
      get inventory_root_path
      assert_select ".nav-item a[href=?]", inventory_setup_path, count: 0
      sign_out @world.admin.user
      sign_in @world.keeper.user
      get inventory_root_path
      assert_select "a[href=?]", inventory_setup_path, count: 0
    end
    item = GatherPack::Features.all.find { |feature| feature.key == :inventory }.setup_items.first
    assert_equal :inventory_setup_path, item.path
  end

  test "Machines is in the menu and on the Inventory page for anyone who can use inventory" do
    nav = GatherPack::Features.all.find { |feature| feature.key == :inventory }.nav_items.find { |item| item.label == "Machines" }
    assert_kind_of Proc, nav.path
    with_inventory(@world) do
      sign_in @world.member.user
      get inventory_root_path
      path = inventory_machine_type_path(location_type("machine"))
      assert_select ".nav-item a[href=?]", path, text: /Machines/
      assert_select "a.btn[href=?]", path, text: /Machines/
    end
  end

  test "yes/no settings show Yes and No, and the four lists are linked" do
    with_inventory(@world) do
      sign_in @world.admin.user
      get inventory_setup_path
      assert_select "select[name='settings[inventory_used_needs_reason]'] option", text: "Yes"
      assert_select "select[name='settings[inventory_used_needs_reason]'] option", text: "No"
      assert_select "select[name='settings[inventory_used_needs_reason]'] option", text: "true", count: 0
      assert_select "#inventory_lists a", text: "Place Types"
      assert_select "#inventory_lists a", text: "Stock Units"
      assert_select "#inventory_lists a", text: "Part Conditions"
      assert_select "#inventory_lists a", text: "Reading Types"
    end
  end

  test "the machine and default unit settings are gone: they're the place types and stock units lists" do
    %i[inventory_machines inventory_machine_name inventory_machine_name_plural inventory_default_unit].each do |key|
      assert_nil Settings.get(key), key
    end
  end

  test "the settings page points to Setup when pickers are there" do
    skip "needs the settings seam" unless Settings.respond_to?(:page)
    with_inventory(@world) do
      sign_in @world.admin.user
      get settings_path
      assert_select "a[href=?]", inventory_setup_path
    end
  end
end
