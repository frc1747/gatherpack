require "test_helper"
require "support/inventory_world"

class Inventory::FeatureTest < ActiveSupport::TestCase
  include SettingsTestHelper

  setup do
    @stub = GatherPack::Feature.new(key: :stub_purchasing, label: "Stub", default_enabled: false, nav_section: "Purchasing", nav_position: 10,
      nav_items: [ GatherPack::Feature::NavItem.new(label: "Stub", path: :root_path, icon: "star") ])
    GatherPack::Features.register(@stub)
  end

  teardown { GatherPack::Features.instance_variable_get(:@plugins).delete(:stub_purchasing) }

  def inventory
    GatherPack::Features.all.find { |feature| feature.key == :inventory }
  end

  def section_names
    GatherPack::Features.nav_sections.map(&:first)
  end

  test "Inventory alone, Purchasing beside another enabled feature with Purchasing items, Inventory again when it's off" do
    with_settings(feature_inventory: "true", feature_stub_purchasing: "false") do
      assert_equal "Inventory", inventory.nav_section
      assert_includes section_names, "Inventory"
    end

    with_settings(feature_inventory: "true", feature_stub_purchasing: "true") do
      assert_equal "Purchasing", inventory.nav_section
      items = GatherPack::Features.nav_sections.to_h["Purchasing"].map(&:label)
      assert_equal [ "Stub", "Inventory", "Machines" ] + manager_labels, items
      assert_not_includes section_names, "Inventory"
    end

    with_settings(feature_inventory: "true", feature_stub_purchasing: "false") do
      assert_equal "Inventory", inventory.nav_section
    end
  end

  # The manager pages are in the menu only where an entry can be hidden per
  # person.
  def manager_labels
    GatherPack::Feature::NavItem.members.include?(:visible) ? %w[Reorder Items Places Changes Setup] : []
  end

  test "manager pages are offered only to managers" do
    world = Object.new.extend(InventoryWorld).build_inventory_world
    with_settings(feature_inventory: "true", inventory_managers: "#{world.keeper_badge.name} > #{world.club.name}") do
      Inventory::Current.reset
      assert_equal %w[Reorder Items Places Changes], Inventory.manager_pages(world.keeper).map(&:first)
      assert_equal %w[Reorder Items Places Changes], Inventory.manager_pages(world.manager).map(&:first)
      assert_empty Inventory.manager_pages(world.member)

      menu = inventory.nav_items
      if GatherPack::Feature::NavItem.members.include?(:visible)
        assert_not menu.find { |item| item.label == "Reorder" }.visible?(world.member.user)
        assert menu.find { |item| item.label == "Reorder" }.visible?(world.keeper.user)
      else
        assert_equal %w[Inventory Machines], menu.map(&:label)
      end
    end
  ensure
    Inventory::Current.reset
  end

  test "the flag is off by default and gates the menu" do
    assert_equal false, inventory.default_enabled
    with_settings(feature_inventory: "false") do
      assert_not_includes section_names, "Inventory"
      assert_not Inventory.enabled?
    end
  end

  test "settings are registered with their defaults" do
    {
      inventory_users: "", inventory_managers: "", inventory_member_kinds: "used, moved, counted",
      inventory_member_unit_actions: "install, take_off, move, check, mark_for_repair",
      inventory_used_needs_reason: "false", inventory_undo_minutes: "10", inventory_reorder_notice: "daily",
      inventory_default_unit: "each"
    }.each { |key, default| assert_equal default, Settings.get(key).default_value, key }
    assert_equal %w[used moved counted], Inventory::Config.member_kinds
  end

  test "hook targets and events are in the catalog, and the reorder list has Print and Download CSV" do
    %w[items - running_low items - out_of_stock items - restocked stock_movements - count_differs
       item_units - needs_repair item_units - installed item_units - removed].each_slice(3) do |words|
      assert_includes Hook.catalog, words.join(" ")
    end
    Inventory::HOOK_TARGETS.each { |target| assert_includes Hook.catalog, "#{target} - create" }
    assert_not_includes Hook.catalog, "stock_levels - create"
    assert_equal %i[print csv], Inventory.extensions.reorder_actions.map(&:key).first(2)
  end

  test "the managers' digest runs daily from config/recurring.d" do
    task = GatherPack::RecurringSchedule.tasks[:inventory_digest]

    assert_equal "InventoryDigestJob", task[:class]
    assert_equal "at 7am every day", task[:schedule]
  end
end
