require "test_helper"
require "support/inventory_world"

# Inventory on the My GatherPack home page and menu: the reorder to-do, and
# the inventory pages under their own section heading.
class MyGatherpackInventoryTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
    @sections = MyGatherpack.sections.dup
  end

  teardown do
    MyGatherpack.sections.replace(@sections)
  end

  def home(**settings, &block)
    with_inventory(@world, feature_my_gatherpack: "true", **settings, &block)
  end

  def row_titles
    css_select("[data-home-column=todo] .mg-row-title").map { |title| title.text.squish }
  end

  def low_item(name, team: @world.club)
    Item.create!(team: team, name: name, home_location: @world.bin1, reorder_point: 5)
  end

  test "an inventory manager gets one row for the reorder list that opens Reorder" do
    home do
      @world.screws.update!(reorder_point: 10)
      low_item "Washer"
      low_item "Nut"
      sign_in @world.keeper.user

      get root_path

      assert_equal [ "3 items running low" ], row_titles
      assert_select ".mg-row", text: /3 items running low/ do
        assert_select "a.btn[href=?]", inventory_reorder_path, text: /Open Reorder/
      end
      assert_select "h1", text: /You have 1 thing to do/
    end
  end

  test "one item is singular, and an item with enough stock isn't counted" do
    home do
      stock!(@world, 50)
      low_item "Washer"
      sign_in @world.keeper.user

      get root_path

      assert_equal [ "1 item running low" ], row_titles
    end
  end

  test "nothing running low gives no row" do
    home do
      stock!(@world, 50)
      sign_in @world.keeper.user

      get root_path

      assert_empty row_titles
    end
  end

  test "a team manager and an admin get the row, and only for the teams they manage" do
    home do
      low_item "Washer", team: @world.robotics
      sign_in @world.manager.user
      get root_path
      assert_equal [ "1 item running low" ], row_titles

      sign_in @world.admin.user
      get root_path
      assert_equal [ "2 items running low" ], row_titles
    end
  end

  test "members, teammates and outsiders get no row" do
    home do
      low_item "Washer", team: @world.robotics
      [ @world.member, @world.teammate, @world.builder, @world.outreacher, @world.outsider ].each do |person|
        sign_in person.user
        get root_path
        assert_response :success
        assert_empty row_titles, "#{person.first_name} should have no inventory row"
      end
    end
  end

  test "nothing with inventory off" do
    with_settings(feature_inventory: "false", feature_my_gatherpack: "true", inventory_managers: "#{@world.keeper_badge.name} > #{@world.club.name}") do
      Inventory::Current.reset
      sign_in @world.keeper.user
      get root_path
      assert_empty row_titles
    ensure
      Inventory::Current.reset
    end
  end

  test "the row costs the same number of queries for 4 items as for 16" do
    home do
      view = ApplicationController.new.view_context
      user = @world.keeper.user
      view.define_singleton_method(:current_user) { user }
      view.define_singleton_method(:inventory_reorder_path) { "/inventory/reorder" }
      rows = -> {
        Inventory::Current.reset
        count_queries { view.my_gatherpack_inventory_items }
      }

      3.times { |index| low_item "Few #{index}" }
      few = rows.call
      12.times { |index| low_item "Many #{index}" }
      many = rows.call

      assert_equal 16, view.my_gatherpack_inventory_items.first.title.to_i
      assert_equal few, many
    end
  end

  test "the inventory pages sit together under their section heading, never on top or in Manage" do
    home do
      labels = %w[Reorder Items Places Changes]

      [ @world.keeper, @world.manager, @world.admin ].each do |person|
        menu = MyGatherpack::Menu.new(person.user)
        assert_empty (menu.top + menu.manage).map(&:label) & labels, "#{person.first_name}: inventory pages outside their section"
        # Purchasing when orders shares it, Inventory on its own.
        section = menu.sections.to_h.slice("Purchasing", "Inventory").values.flatten.map(&:label)
        assert_equal labels, section & labels
      end
      assert_not MyGatherpack::Menu.new(@world.keeper.user).manages_anything?
    end
  end

  private

  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end
