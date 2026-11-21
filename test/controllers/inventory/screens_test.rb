require "test_helper"
require "support/inventory_world"

# The inventory screens laid out to the screen standard: record pages show
# Edit, the job and More; Undo is a link in the confirmation after a change;
# unit action pages have Cancel and the action; setup has one footer; lists
# don't repeat links to the other lists.
class Inventory::ScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
  end

  def more_items
    css_select(".screen-action-row .dropdown-menu li").map { |item| item.text.strip }
  end

  test "the item page footer has Edit and More, with Delete last behind its confirm" do
    with_inventory(@world) do
      washers = Item.create!(team: @world.club, name: "Washer", home_location: @world.bin1)
      sign_in @world.admin.user
      get inventory_item_path(washers)
      assert_response :success

      assert_select ".card-footer.screen-action-row" do
        assert_select "> a.btn", 1
        assert_select "> a.btn-warning[href=?]", edit_inventory_item_path(washers), text: "Edit"
        assert_select ".dropdown > button", text: "More"
      end
      assert_equal [ "Label", "Add where to buy", "Delete" ], more_items
      assert_select ".dropdown-menu form[action=?][data-turbo-confirm=?]", inventory_item_path(washers), "Delete Washer?" do
        assert_select "input[name=_method][value=delete]"
        assert_select "button.text-danger", text: "Delete"
      end
      # The stock-change buttons stay together above the history.
      kinds = css_select("a.btn-primary[href*='kind=received'], a.btn-primary[href*='kind=added'], a.btn-primary[href*='kind=removed']")
      assert_equal 3, kinds.size
      assert_operator response.body.index("kind=received"), :<, response.body.index(">History<")
      assert_select ".screen-action-row a[href*='kind=']", count: 0

      # With history it can't be deleted, so More holds the rest.
      stock!(@world, 10)
      get inventory_item_path(@world.screws)
      assert_equal [ "Label", "Add where to buy" ], more_items
    end
  end

  test "a member's place page has Count this place first in the row and no second Count bar" do
    with_inventory(@world) do
      stock!(@world, 10)
      sign_in @world.member.user
      get inventory_location_path(@world.bin1)
      assert_select ".card-footer.screen-action-row > a.btn-primary:first-child[href=?]", count_inventory_location_path(@world.bin1),
        text: "Count this place"
      assert_select ".screen-action-row .dropdown", count: 0
      assert_select ".inventory-bar", count: 0
      assert_select "a", text: "Count this place", count: 1
    end
  end

  test "a member sees no footer on the item page" do
    with_inventory(@world) do
      stock!(@world, 10)
      sign_in @world.member.user
      get inventory_item_path(@world.screws)
      assert_select ".screen-action-row", count: 0
      assert_select "a", text: "Undo", count: 0
    end
  end

  test "the place page footer has Edit, Count this place and More, with Delete last behind its confirm" do
    with_inventory(@world) do
      stock!(@world, 10)
      sign_in @world.admin.user
      get inventory_location_path(@world.bin1)
      assert_response :success

      assert_select ".card-footer.screen-action-row" do
        assert_select "> a.btn-warning[href=?]", edit_inventory_location_path(@world.bin1), text: "Edit"
        assert_select "> a.btn-primary[href=?]", count_inventory_location_path(@world.bin1), text: "Count this place"
      end
      assert_equal [ "Count this place", "Add a place inside", "Add an item here", "Label" ], more_items
      assert_select ".dropdown-menu li.d-md-none", text: "Count this place"
      # Count is in More on a phone, so it's also one large tap at the bottom.
      assert_select ".inventory-has-bar .inventory-bar.d-md-none a.btn-primary.btn-lg[href=?]", count_inventory_location_path(@world.bin1),
        text: "Count this place"

      shelf = Location.create!(team: @world.club, name: "Shelf", parent: @world.cabinet)
      get inventory_location_path(shelf)
      assert_select ".inventory-bar", count: 0
      assert_select ".card-footer.screen-action-row > a.btn-warning", text: "Edit"
      assert_equal "Delete", more_items.last
      assert_select ".dropdown-menu form[action=?][data-turbo-confirm=?]", inventory_location_path(shelf), "Delete Shelf?" do
        assert_select "button.text-danger", text: "Delete"
      end
    end
  end

  test "Undo is a link in the confirmation after a stock change, and it works" do
    with_inventory(@world) do
      stock!(@world, 10)
      sign_in @world.member.user
      post inventory_movements_path, params: { kind: "used", item_id: @world.screws.id, location_id: @world.bin1.id, quantity: "4",
        return_to: inventory_item_path(@world.screws) }
      follow_redirect!
      assert_select ".inventory-toast.alert", text: /Used 4 from Bin 1/
      undo = css_select(".inventory-toast a.alert-link[data-turbo-method=post]").sole
      assert_equal "Undo", undo.text.strip
      assert_select ".card-footer a, .card-footer button", text: "Undo", count: 0

      post undo["href"]
      assert_redirected_to inventory_item_path(@world.screws)
      assert_equal 10, @world.screws.stock_at(@world.bin1)
      follow_redirect!
      assert_select ".alert", text: /Undone: Used 4 from Bin 1/
      assert_select ".inventory-toast", count: 0
    end
  end

  test "unit action pages have Cancel back to the unit and still submit, and the confirmation carries Undo" do
    motor = tracked_item!(@world, name: "Motor", units: 1)
    unit = motor.item_units.sole
    with_inventory(@world) do
      sign_in @world.admin.user
      %w[install move check mark_for_repair retire].each do |act|
        get inventory_unit_action_form_path(unit, act: act)
        assert_response :success, act
        assert_select "#unit_action_form a.btn-lg.btn-secondary[href=?]", inventory_unit_path(unit), text: "Cancel"
        assert_select "#unit_action_form a.btn-warning", count: 0
        assert_select "#unit_action_form input[type=submit].btn-lg"
      end

      post move_inventory_unit_path(unit), params: { location_id: @world.bin2.id }
      assert_redirected_to inventory_unit_path(unit)
      assert_equal @world.bin2, unit.reload.location
      follow_redirect!
      assert_select ".inventory-toast", text: /Moved to Bin 2/
      # inventory.css keeps the message at the top and out of print.
      assert_select "link[rel=stylesheet][href*=?]", "inventory"
      undo = css_select(".inventory-toast a[data-turbo-method=post]").sole
      assert_equal undo_inventory_unit_event_path(unit.events.last), undo["href"]
      assert_select "a.btn-warning[href=?]", edit_inventory_unit_path(unit), text: "Edit"

      post undo["href"]
      assert_equal @world.bin1, unit.reload.location
    end
  end

  test "a unit action someone may not undo keeps its plain notice" do
    motor = tracked_item!(@world, name: "Motor", units: 1)
    unit = motor.item_units.sole
    with_inventory(@world, inventory_undo_minutes: "0") do
      sign_in @world.member.user
      post move_inventory_unit_path(unit), params: { location_id: @world.bin2.id }
      assert_equal "Moved to Bin 2", flash[:notice]
      follow_redirect!
      assert_select ".inventory-toast", count: 0
    end
  end

  test "setup saves with one footer" do
    skip "plain page only" if Settings.respond_to?(:page)
    with_inventory(@world) do
      sign_in @world.admin.user
      get inventory_setup_path
      assert_select "form[action=?]", inventory_setup_path do
        assert_select "input[type=submit]", 1
        assert_select ".card-footer input[type=submit].btn-primary[value=Save]"
        assert_select ".card-footer a.btn-secondary[href=?]", setup_path, text: "Cancel"
      end
      assert_select "main .btn-success", count: 0
      assert_select "button.btn-sm.btn-outline-secondary", text: "Add a row"

      patch inventory_setup_path, params: { settings: { inventory_undo_minutes: "15" } }
      assert_redirected_to inventory_setup_path
      assert_equal "15", Settings[:inventory_undo_minutes]
    end
  end

  test "lists don't repeat links to the other lists, and Changes prints once" do
    with_inventory(@world) do
      stock!(@world, 10)
      sign_in @world.admin.user
      [ inventory_items_path, inventory_locations_path, inventory_reorder_path, inventory_movements_path, inventory_root_path,
        inventory_location_path(@world.bin1) ].each do |path|
        get path
        assert_response :success, path
        assert_select "nav[aria-label='Inventory pages']", count: 0
        assert_select "main a.btn[href=?]", inventory_setup_path, count: 0
      end

      get inventory_items_path
      assert_equal [ "New item", "Search", "Clear Search" ],
        css_select("form .card-footer .btn").map { |button| (button["value"] || button.text).strip }.first(3)

      get inventory_movements_path
      assert_select "a.btn, button.btn", text: "Print", count: 1
      assert_select "a.btn", text: "Download CSV", count: 1
      get inventory_movements_path(print: 1)
      assert_select "a.btn, button.btn", text: "Print", count: 1
      assert_select "button.btn-dark", text: "Print"
    end
  end

  test "print views have their controls at the top and no Back button" do
    with_inventory(@world) do
      stock!(@world, 1)
      @world.screws.update!(reorder_point: 5)
      sign_in @world.admin.user
      get inventory_reorder_path(print: 1, items: { @world.screws.id => 4 })
      assert_response :success
      assert_select "button.btn-dark", text: "Print"
      assert_select "a", text: "Back to the list", count: 0
      assert_select ".table-responsive table"

      get inventory_labels_path(items: [ @world.screws.id ])
      assert_select "button.btn-dark", text: "Print"
    end
  end
end
