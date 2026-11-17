require "test_helper"
require "support/inventory_world"

# The units section registered for the item page, rendered as the item
# page renders its panels: with the locals item: and viewer:.
class Inventory::UnitsItemPanelTest < ActiveSupport::TestCase
  include InventoryWorld

  setup do
    @world = build_inventory_world
    @motor = tracked_item!(@world, name: "Motor", units: 4)
  end

  def panel(item, viewer)
    with_inventory(@world) do
      assert Inventory.extensions.item_panels(item, viewer).any? { |p| p.key == :units }
      Nokogiri::HTML(ApplicationController.render(partial: "inventory/units/item_panel", locals: { item: item, viewer: viewer }))
    end
  end

  test "groups units by place: available, on each machine, in repair, retired" do
    one, two, three, four = @motor.item_units.order(:code).to_a
    two.install!(into: @world.robot, by: @world.admin)
    three.mark_for_repair!(by: @world.admin, note: "Hot")
    four.retire!(by: @world.admin, note: "Burnt")

    headings = panel(@motor, @world.member).css("h3").map { |h| h.text.squish }
    assert_equal [ "Available 1", "On Robot 1", "In repair 1", "Retired 1" ], headings
    assert_includes panel(@motor, @world.member).text, one.code
  end

  test "managers get the tracking switch and readings link; members don't" do
    item = tracked_item!(@world, name: "Gearbox", units: 0)
    manager_view = panel(item, @world.keeper)
    assert manager_view.at_css("form[action='#{Rails.application.routes.url_helpers.inventory_item_tracking_path(item)}']")
    assert manager_view.at_css("a", text: "Edit readings")

    member_view = panel(item, @world.member)
    assert_nil member_view.at_css("form")
    assert_nil member_view.at_css("a", text: "Edit readings")
  end

  test "an untracked item shows Track each piece to managers only" do
    with_inventory(@world) do
      assert_not Inventory.extensions.item_panels(@world.screws, @world.member).any? { |p| p.key == :units }
    end
    assert panel(@world.screws, @world.keeper).at_css("button", text: "Track each piece")
  end

  test "units inside a stored part show under it, not as on a machine or available" do
    one, two = @motor.item_units.order(:code).to_a
    holder = tracked_item!(@world, name: "Module", units: 1).item_units.first
    one.install!(into: holder, by: @world.admin)
    two.install!(into: @world.robot, by: @world.admin)

    view = panel(@motor, @world.member)
    headings = view.css("h3").map { |h| h.text.squish }
    assert_equal [ "Available 2", "Inside other parts 1", "On Robot 1" ], headings
    assert_includes view.text.squish, "MOT-1 New in MOD-1"
    assert_not headings.any? { |heading| heading.start_with?("On Bin") }
  end
end
