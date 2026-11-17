require "test_helper"
require "support/orders_world"

# Orders on the My GatherPack home page: the to-dos, Your orders and the menu.
class MyGatherpackOrdersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup do
    host! "localhost"
    @world = build_orders_world
    @sections = MyGatherpack.sections.dup
  end

  teardown do
    MyGatherpack.sections.replace(@sections)
  end

  def home(**settings, &block)
    with_orders(@world, feature_my_gatherpack: "true", orders_requesters: @world.robotics.name, **settings, &block)
  end

  def row_titles
    css_select("[data-home-column=todo] .mg-row-title").map { |title| title.text.squish }
  end

  test "an approver gets a Review row for a request they can decide, with its total and team" do
    home do
      request = submitted_request(@world, title: "Gears", lines: [ { description: "Gear", price: 12 } ])
      sign_in @world.mentor.user

      get root_path

      assert_select ".mg-row", text: /Gears/ do
        assert_select "a.btn", text: "Review"
        assert_select "a[href=?]", orders_request_path(request)
        assert_select ".mg-row-detail", text: /\$12\.00 · #{@world.robotics.name}/
      end
      assert_select "h1", text: /You have 1 thing to do/
    end
  end

  test "nobody gets an approval row for their own request or a relative's" do
    home do
      submitted_request(@world, title: "Gears")
      submitted_request(@world, title: "Mentor's own", by: @world.mentor)
      sign_in @world.requester.user
      get root_path
      assert_not_includes row_titles, "Gears"

      sign_in @world.parent.user
      get root_path
      assert_not_includes row_titles, "Gears"

      sign_in @world.mentor.user
      get root_path
      assert_equal [ "Gears" ], row_titles
    end
  end

  test "a requester with changes requested gets an Update row with the comment, shortened" do
    home do
      request = submitted_request(@world, title: "Gears")
      request.decide!(:changes_requested, by: @world.mentor, comment: "Please find a cheaper one. " * 10)
      sign_in @world.requester.user

      get root_path

      assert_select ".mg-row", text: /Gears/ do
        assert_select "a.btn", text: "Update"
        assert_select ".mg-row-detail", text: /Please find a cheaper one\..*\.\.\.\z/
      end
      assert_select "[data-home-column=todo] .mg-row", text: /Gears/, count: 1
    end
  end

  test "30 items to buy are one row for a buyer, who opens To buy" do
    home do
      approved_request(@world, lines: Array.new(30) { |index| { description: "Bolt #{index}", price: 1 } })
      sign_in @world.buyer.user

      get root_path

      assert_equal [ "30 items to buy" ], row_titles
      assert_select "a.btn[href=?]", to_buy_orders_purchases_path, text: /Open To buy/
      assert_select "h1", text: /You have 1 thing to do/

      sign_in @world.requester.user
      get root_path
      assert_not_includes row_titles, "30 items to buy"
    end
  end

  test "a buyer's problem delivery is a Resolve row for them" do
    home do
      request = approved_request(@world, title: "Gears")
      buy(@world, request.order_lines.to_a, vendor: @world.preferred_vendor)
      line = request.reload.order_lines.first
      line.record_delivery!(by: @world.requester, quantity: 1, received_on: Date.current, condition: :damaged)
      sign_in @world.buyer.user

      get root_path

      assert_select ".mg-row", text: /Gears/ do
        assert_select "a.btn", text: "Resolve"
        assert_select ".mg-row-detail", text: /Problem with a delivery/
      end
    end
  end

  test "the requester and a watcher get one receive row linking to their own list; a teammate gets none" do
    home do
      request = approved_request(@world, lines: [ { description: "Gear", price: 5 }, { description: "Nut", price: 1 } ])
      buy(@world, request.order_lines.to_a, vendor: @world.preferred_vendor)
      request.follow!(@world.builder)
      sign_in @world.requester.user

      get root_path

      assert_equal [ "2 items to receive" ], row_titles
      assert_select "a.btn[href=?]", orders_deliveries_path(mine: 1), text: /Receive/

      sign_in @world.builder.user
      get root_path
      assert_equal [ "2 items to receive" ], row_titles

      sign_in @world.teammate.user
      get root_path
      assert_not_includes row_titles, "2 items to receive"
      assert_select "h1", text: /all caught up/
    end
  end

  test "to-dos sort by needed by with blanks last, and a request past its date comes first" do
    home do
      submitted_request(@world, title: "No date")
      submitted_request(@world, title: "Later", needed_by: 10.days.from_now.to_date)
      submitted_request(@world, title: "Overdue", needed_by: 2.days.ago.to_date)
      sign_in @world.mentor.user

      get root_path

      assert_equal [ "Overdue", "Later", "No date" ], row_titles
      assert_select "h1", text: /3 things to do/
    end
  end

  test "Your orders shows only New request to a requester with nothing active" do
    home do
      sign_in @world.requester.user

      get root_path

      assert_select "[data-home-section=orders]" do
        assert_select "a.btn", text: "New request"
        assert_select ".mg-row", count: 0
      end
    end
  end

  test "Your orders shows nothing to someone who can't request and has nothing active" do
    home do
      sign_in @world.outsider.user

      get root_path

      assert_select "[data-home-section=orders]", count: 0
    end
  end

  test "Your orders lists the five most recent active requests and leaves the heading's count alone" do
    home do
      7.times do |index|
        submitted_request(@world, title: "Request #{index}").update_columns(updated_at: (10 - index).hours.ago)
      end
      draft_request(@world, title: "A draft")
      sign_in @world.requester.user

      get root_path

      assert_select "[data-home-section=orders]" do
        assert_select ".mg-row", count: 5
        assert_select ".mg-row-title", text: "Request 6"
        assert_select ".mg-row-title", text: "Request 3"
        assert_select ".mg-row-title", text: "A draft"
        %w[ Request\ 2 Request\ 1 Request\ 0 ].each { |title| assert_select ".mg-row-title", text: title, count: 0 }
        assert_select "a[href=?]", orders_requests_path(mine: 1), text: "My requests"
        assert_select "a.btn", text: "New request"
        assert_select ".mg-row-detail", text: "Waiting for approval", minimum: 1
      end
      assert_select "h1", text: /all caught up/
    end
  end

  test "Your orders shows a draft to its requester but not as a to-do" do
    home do
      draft_request(@world, title: "A draft")
      sign_in @world.requester.user

      get root_path

      assert_select "[data-home-section=orders] .mg-row", text: /A draft/
      assert_select "[data-home-column=todo]", count: 0
    end
  end

  test "the My Orders card shows with My GatherPack off and Home shows with it on" do
    with_orders(@world, feature_my_gatherpack: "false") do
      submitted_request(@world, title: "Gears")
      sign_in @world.mentor.user

      get root_path
      assert_select ".card-header h2", text: "My Orders"
      assert_select ".mg-row", count: 0
    end

    home do
      get root_path
      assert_select ".card-header h2", text: "My Orders", count: 0
      assert_select ".mg-row-title", text: "Gears"
    end
  end

  test "nothing shows with orders off" do
    home(feature_orders: "false") do
      sign_in @world.mentor.user

      get root_path

      assert_select ".mg-row", count: 0
      assert_select "[data-home-section=orders]", count: 0
    end
  end

  test "the number of queries doesn't grow with the number of requests" do
    home do
      lines = [ { description: "Gear", price: 5 }, { description: "Nut", price: 1 } ]
      3.times { |index| submitted_request(@world, title: "First #{index}", lines: lines) }
      sign_in @world.mentor.user
      few = count_queries { get root_path }
      assert_equal 3, row_titles.size

      12.times { |index| submitted_request(@world, title: "More #{index}", lines: lines) }
      many = count_queries { get root_path }
      assert_equal 15, row_titles.size

      assert_operator many, :<=, few
    end
  end

  test "every orders page is under the Purchasing heading, never on top or in Manage" do
    home do
      orders = [ "Orders", "To approve", "To buy", "To receive", "Vendors", "Funding sources", "Reports" ]
      purchasing = ->(menu) { menu.sections.to_h.fetch("Purchasing", []).map(&:label) }

      [ @world.mentor, @world.buyer, @world.requester, @world.manager ].each do |person|
        menu = MyGatherpack::Menu.new(person.user)
        assert_empty (menu.top + menu.manage).map(&:label) & orders, "#{person.first_name}: orders items outside Purchasing"
        assert_includes purchasing.(menu), "Orders"
        assert_includes purchasing.(menu), "To receive"
      end
      assert_includes purchasing.(MyGatherpack::Menu.new(@world.buyer.user)), "To buy"
      assert_not MyGatherpack::Menu.new(@world.mentor.user).manages_anything?

      # Hidden from non-approvers where feature/orders gives To approve a visible check.
      to_approve = GatherPack::Features.nav_sections.flat_map(&:last).find { |item| item.label == "To approve" }
      if to_approve.respond_to?(:visible) && to_approve.visible
        assert_not_includes purchasing.(MyGatherpack::Menu.new(@world.requester.user)), "To approve"
      end
    end
  end

  test "an approver sees a re-approval row for a changed item; the requester doesn't" do
    home do
      request = approved_request(@world, title: "Kit", lines: [ { description: "Kit", price: 100 } ])
      request.order_lines.first.change_quantity!(3, by: @world.buyer)
      sign_in @world.mentor.user

      get root_path

      assert_select "[data-home-column=todo] .mg-row", text: /Kit/ do
        assert_select "a.btn", text: "Review"
        assert_select "a[href=?]", orders_request_path(request)
        assert_select ".mg-row-detail", text: "Needs re-approval"
      end

      sign_in @world.requester.user
      get root_path
      assert_select "[data-home-column=todo]", count: 0
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
