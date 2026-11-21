require "application_system_test_case"
require "support/inventory_world"

# Inventory spec §7, system tests for stock. The member screens run at a
# phone's size (§3.9); the manager screens at the default desktop size.
class InventoryStockTest < ApplicationSystemTestCase
  include InventoryWorld
  include Warden::Test::Helpers

  setup do
    # The app builds URLs for localhost; browse there so redirects stay on-host.
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    @world = build_inventory_world
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  teardown do
    Capybara.app_host = nil
    Warden.test_reset!
  end

  def phone!
    page.driver.browser.manage.window.resize_to(390, 800)
  end

  def assert_tappable(element)
    assert_operator element.native.size.height, :>=, 44
  end

  def assert_bar_fixed
    assert_equal "fixed", evaluate_script("getComputedStyle(document.querySelector('.inventory-bar')).position")
  end

  test "search finds an item by part number and shows its places on a phone" do
    with_inventory(@world) do
      stock!(@world, 14)
      stock!(@world, 3, location: @world.bin2)
      phone!
      login_as(@world.member.user, scope: :user)

      visit inventory_root_path
      assert_equal "q", evaluate_script("document.activeElement.id")
      fill_in "q", with: "M4-12"
      within "#inventory-results" do
        assert_text "M4 screw"
        assert_text "Shop › Cabinet › Bin 1: 14"
        assert_text "Shop › Cabinet › Bin 2: 3"
      end
      assert_tappable find("#inventory-results a", match: :first)
      click_on "M4 screw"
      assert_selector "h1", text: "M4 screw"
      assert_text "17 in stock"
    end
  end

  test "record used from the item page, then Undo, on a phone" do
    with_inventory(@world) do
      stock!(@world, 14)
      phone!
      login_as(@world.member.user, scope: :user)

      visit inventory_item_path(@world.screws)
      assert_bar_fixed
      assert_tappable find_link("Used")
      click_on "Used"
      assert_selector "h1", text: "Used: M4 screw"
      assert_text "Shop › Cabinet › Bin 1"
      assert_equal "1", find_field("quantity").value
      3.times { find("button[aria-label='One more']").click }
      assert_equal "4", find_field("quantity").value
      assert_bar_fixed
      click_on "Done"

      within ".inventory-toast" do
        assert_text "Used 4 from Bin 1"
        assert_operator evaluate_script("document.querySelector('.inventory-toast').getBoundingClientRect().top"), :<, 200
        assert_operator evaluate_script("document.querySelector('.inventory-toast').getBoundingClientRect().top"), :<,
          evaluate_script("document.querySelector('.inventory-history').getBoundingClientRect().top")
        click_on "Undo"
      end
      assert_text "Undone: Used 4 from Bin 1"
      assert_text "14 in stock"
      within ".inventory-history" do
        assert_text "Undone"
      end
      assert_equal 14, @world.screws.stock_at(@world.bin1)
    end
  end

  test "open a place page by its URL and Count this place, with one difference, on a phone" do
    with_inventory(@world) do
      stock!(@world, 14)
      nuts = Item.create!(team: @world.club, name: "M4 nut", home_location: @world.bin1)
      stock!(@world, 20, item: nuts)
      phone!
      login_as(@world.member.user, scope: :user)

      visit inventory_location_path(@world.bin1)
      assert_selector "h1", text: "Bin 1"
      within("#place-items") do
        assert_text "M4 nut"
        assert_text "M4 screw"
      end
      within(".inventory-bar") do
        assert_tappable find_link("Count this place")
        click_on "Count this place"
      end

      assert_text "1 of 2"
      assert_selector "h2", text: "M4 nut"
      assert_equal "", find_field("How many do you see?").value
      fill_in "How many do you see?", with: "20"
      click_on "Next"
      assert_text "2 of 2"
      assert_selector "h2", text: "M4 screw"
      fill_in "How many do you see?", with: "11"
      click_on "Next"

      within("[data-inventory-count-target=summary]") do
        assert_text "M4 screw: 14 → 11"
        assert_text "-3"
        assert_text "1 matched."
        assert_no_text "M4 nut:"
      end
      click_on "Save counts"
      assert_text "Saved 2 counts (1 difference)."
      assert_equal 11, @world.screws.stock_at(@world.bin1)
      assert_equal 20, nuts.stock_at(@world.bin1)
      assert_equal [ -3, 0 ], StockMovement.counted.order(:quantity).pluck(:quantity)
    end
  end

  test "move between places on a phone" do
    with_inventory(@world) do
      stock!(@world, 10)
      phone!
      login_as(@world.member.user, scope: :user)

      visit inventory_item_path(@world.screws)
      click_on "Move"
      assert_selector "h1", text: "Moved: M4 screw"
      select "Shop › Cabinet › Bin 2", from: "To"
      fill_in "quantity", with: "4"
      assert_bar_fixed
      click_on "Move"

      assert_text "Moved 4 from Bin 1 to Bin 2"
      within "#stock-by-place" do
        assert_text "Shop › Cabinet › Bin 1"
        assert_text "Shop › Cabinet › Bin 2"
      end
      assert_equal 6, @world.screws.stock_at(@world.bin1)
      assert_equal 4, @world.screws.stock_at(@world.bin2)
    end
  end

  test "a manager builds a place tree, adds an item and prints labels" do
    with_inventory(@world) do
      login_as(@world.keeper.user, scope: :user)

      visit inventory_locations_path
      click_on "New place"
      fill_in "Name", with: "Electrical cart"
      fill_in "Code", with: "E"
      select @world.club.name, from: "Team"
      click_on "Save place"
      assert_text "Electrical cart was added."

      click_on "More"
      click_on "Add a place inside"
      fill_in "Name", with: "Drawer 1"
      fill_in "Code", with: "E-1"
      click_on "Save place"
      assert_text "Drawer 1 was added."
      assert_text "Electrical cart › Drawer 1"

      click_on "More"
      click_on "Add an item here"
      fill_in "Name", with: "Red wire"
      select "foot", from: "Stock unit"
      fill_in "Order more at", with: "20"
      select @world.club.name, from: "Team"
      click_on "Save item"
      assert_text "Red wire was added."
      assert_text "Electrical cart › Drawer 1"
      assert_text "Home"

      visit inventory_locations_path
      find("input[aria-label='Label for Electrical cart']").check
      check "Include the places inside"
      click_on "Print labels"
      within "#labels" do
        assert_selector ".inventory-label", count: 2
        assert_selector "svg.inventory-qr", count: 2
        assert_text "E-1"
        assert_text "Electrical cart › Drawer 1"
      end
      assert_button "Print"
    end
  end

  test "the reorder list groups low items by vendor; Print, Download CSV and a registered action work" do
    with_inventory(@world) do
      stock!(@world, 4)
      @world.screws.item_sources.create!(vendor_name: "Parts Depot", vendor_part_number: "PD-4")
      Item.create!(team: @world.club, name: "Red wire", reorder_point: 2)
      Item.create!(team: @world.club, name: "Tape", reorder_point: 1, home_location: @world.bin2).tap { |tape| stock!(@world, 9, item: tape, location: @world.bin2) }
      Inventory.extensions.register_reorder_action(:stub, label: "Send to the stub",
        path: ->(rows) { "/inventory?q=#{rows.map { |item, _quantity| item.name }.join(",")}" })
      login_as(@world.keeper.user, scope: :user)

      visit inventory_reorder_path
      assert_equal [ "No source yet", "Parts Depot" ], all("h2").map(&:text)
      assert_text "Red wire"
      assert_text "M4 screw"
      assert_no_text "Tape"
      assert_button "Send to the stub"

      find("input[aria-label='Order Red wire']").uncheck
      find("input[aria-label='How many M4 screw']").fill_in(with: "25")
      click_on "Print"
      assert_selector "h1", text: "Reorder list"
      within("table") do
        assert_text "M4 screw"
        assert_text "PD-4"
        assert_text "25"
        assert_no_text "Red wire"
      end

      visit inventory_reorder_path
      click_on "Download CSV"
      assert_current_path inventory_reorder_path, ignore_query: true

      visit inventory_reorder_path
      click_on "Send to the stub"
      assert_current_path "/inventory?q=M4%20screw,Red%20wire"
    ensure
      Inventory.extensions.instance_variable_get(:@reorder_actions).delete(:stub)
    end
  end

  test "import Preview shows the preview in the browser" do
    with_inventory(@world) do
      csv = Tempfile.new([ "items", ".csv" ])
      csv.write("Name,Place code,Quantity\nZip tie,A-2,6\n")
      csv.close
      login_as(@world.keeper.user, scope: :user)

      visit new_inventory_import_path
      attach_file "file", csv.path
      click_on "Preview"
      assert_selector "h1", text: "Import preview"
      assert_text "1 new item"
      assert_button "Import 1 row"
    end
  end

  test "the Changes page marks a big count where the theme colours rows" do
    with_inventory(@world) do
      stock!(@world, 10)
      record(@world, :counted, 3, person: @world.member)
      login_as(@world.keeper.user, scope: :user)

      visit inventory_movements_path
      assert_selector ".inventory-history .inventory-big-count"
      assert_equal "8px", evaluate_script("getComputedStyle(document.querySelector('.inventory-big-count')).borderLeftWidth")
      refute_equal evaluate_script("getComputedStyle(document.querySelector('.inventory-big-count')).backgroundColor"),
        evaluate_script("getComputedStyle(document.querySelector('.inventory-history')).backgroundColor")
    end
  end

  test "a ticked checkbox on the item form shows a tick" do
    with_inventory(@world) do
      login_as(@world.keeper.user, scope: :user)

      visit new_inventory_item_path
      box = first("input.form-check-input", minimum: 1, visible: :all)
      box.check unless box.checked?
      assert_includes evaluate_script("getComputedStyle(document.querySelector('input.form-check-input:checked')).backgroundImage"), "svg"
      assert_not_equal evaluate_script("getComputedStyle(document.querySelector('input.form-check-input:checked')).backgroundColor"),
        evaluate_script("getComputedStyle(document.body).backgroundColor")
    end
  end
end
