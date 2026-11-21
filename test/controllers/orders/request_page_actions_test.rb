require "test_helper"
require "support/orders_world"

# The request page's header and action row (BL-069): the state in words, one
# job button for the viewer, and the rest in More with Cancel request last.
class Orders::RequestPageActionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  JOBS = [ "Finish request", "Update", "Approve", "Open To buy", "Receive" ].freeze

  setup { @world = build_orders_world }

  # The buttons in the action row outside More, and the items in More (the
  # phone-only copies of hidden buttons left out).
  def action_row
    row = css_select(".card-footer.screen-action-row").sole
    buttons = row.element_children.filter_map do |node|
      button = node.name == "form" ? node.at_css("> button.btn") : node
      button.text.strip if button&.classes&.include?("btn")
    end
    more = row.css(".dropdown-menu > li:not(.d-md-none)").map { |node| node.text.strip }
    [ buttons, more ]
  end

  def assert_one_job(expected)
    buttons, more = action_row
    assert_equal [ expected ], buttons, "buttons outside More"
    assert_empty more & JOBS
    assert_equal "Print", more.reject { |label| label.in?([ "Delete draft", "Cancel request" ]) }.last
    more
  end

  test "the requester's draft shows Finish request, with Delete draft last and its confirm" do
    with_orders(@world) do
      order_request = draft_request(@world)
      sign_in @world.requester.user

      get orders_request_url(order_request)

      assert_select ".card-header h1", order_request.display_title
      assert_select ".card-header .screen-state-line", "Draft"
      assert_one_job "Finish request"
      assert_select ".screen-action-row a.btn-primary[href=?]", edit_orders_request_path(order_request), "Finish request"
      assert_equal [ "Duplicate", "Print", "Delete draft" ], action_row.last
      assert_select ".screen-action-row .dropdown-menu form[action=?][data-turbo-confirm=?]", orders_request_path(order_request), "Delete this draft?"
      assert_select ".screen-action-row .dropdown-menu button.dropdown-item[type=button][data-controller=orders-print][data-action=?]", "orders-print#print", "Print"
      assert_select ".screen-action-row", text: /Cancel request|Edit/, count: 0
      # On a phone the requester's row sits in the bar fixed to the bottom.
      assert_select ".card-footer.orders-bar-fixed"
    end
  end

  test "an approver of a waiting request has the decision bar as their job, and no job button" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.mentor.user

      get orders_request_url(order_request)

      assert_select ".card-header .screen-state-line", /\AWaiting for approval by /
      buttons, more = action_row
      assert_empty buttons
      assert_empty (buttons + more) & JOBS
      assert_select ".screen-action-row a[href*=decision]", 0
      assert_select ".orders-decision-bar" do
        assert_select "button.btn-success[value=approved]", "Approve"
        assert_select "button.btn-secondary[value=changes_requested]", "Ask for changes"
        assert_select "button.btn-danger[value=declined]", "Decline"
      end
      assert_select ".card-footer.orders-bar-fixed", 0
    end
  end

  test "a team manager's Edit, Follow and Cancel request go in More, Cancel request last with its confirm" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.manager.user

      get orders_request_url(order_request)

      buttons, more = action_row
      assert_empty buttons
      assert_equal [ "Edit", "Duplicate", "Follow", "Print", "Cancel request" ], more
      assert_select ".screen-action-row .dropdown-menu form[action=?][data-turbo-confirm=?]",
        cancel_orders_request_path(order_request), "Cancel this request? Nothing on it will be bought." do
        assert_select "button.text-danger", "Cancel request"
      end
    end
  end

  test "with no job for the viewer every action is in More, Cancel request last" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.requester.user

      get orders_request_url(order_request)

      buttons, more = action_row
      assert_empty buttons
      assert_equal "Cancel request", more.last
      assert_includes more, "Order again"
      assert_includes more, "Print"
    end
  end

  test "a buyer of an approved request gets Open To buy" do
    with_orders(@world) do
      order_request = approved_request(@world)
      sign_in @world.buyer.user

      get orders_request_url(order_request)

      assert_select ".card-header .screen-state-line", "Approved, not ordered yet"
      assert_one_job "Open To buy"
      assert_select ".screen-action-row a[href=?]", to_buy_orders_purchases_path
      assert_select "#order_request_purchases a", text: "Open To buy", count: 0
    end
  end

  test "the requester of an ordered request gets Receive" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Gear", price: 10 }, { description: "Belt", price: 5 } ])
      buy(@world, order_request.order_lines.to_a, vendor: @world.preferred_vendor, ordered_on: Date.new(2026, 11, 20))
      sign_in @world.requester.user

      get orders_request_url(order_request)

      assert_select ".card-header .screen-state-line", "Ordered Nov 20: 0 of 2 here"
      assert_one_job "Receive"
      assert_select ".screen-action-row a[href=?]", orders_request_path(order_request, anchor: "receiving")
      assert_select "#receiving"
      _, more = action_row
      assert_not_includes more, "Cancel request"
    end
  end

  test "a draft's form ends Close, Save draft, Submit for approval" do
    with_orders(@world) do
      order_request = draft_request(@world)
      sign_in @world.requester.user

      get edit_orders_request_url(order_request)

      labels = css_select(".orders-bar-fixed .btn").map { |node| node.text.strip }
      assert_equal [ "Close", "Save draft", "Submit for approval" ], labels
      assert_select ".orders-bar-fixed a.btn-secondary[href=?][data-action=?]", orders_requests_path(mine: 1), "order-form#close", "Close"
      assert_select ".orders-bar-fixed button.btn-secondary:not([name=submit_request])", "Save draft"
      assert_select ".orders-bar-fixed button.btn-primary[name=submit_request]", "Submit for approval"

      patch orders_request_url(order_request), params: { order_request: { purpose: "Saved as a draft" } }
      assert_redirected_to edit_orders_request_url(order_request)
      assert order_request.reload.draft?
      assert_equal "Saved as a draft", order_request.purpose
    end
  end

  test "a new request's form offers Close, and opening it makes no draft" do
    with_orders(@world) do
      sign_in @world.requester.user

      assert_no_difference -> { OrderRequest.count } do
        get new_orders_request_url
      end

      labels = css_select(".orders-bar-fixed .btn").map { |node| node.text.strip }
      assert_equal [ "Close", "Save draft", "Submit for approval" ], labels
      assert_select ".orders-bar-fixed a[data-action=?]", "order-form#close"
    end
  end

  test "a form that doesn't save itself keeps Cancel, back to the request" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      order_request.decide!(:changes_requested, by: @world.mentor, comment: "Which size?")
      sign_in @world.requester.user

      get edit_orders_request_url(order_request)

      labels = css_select(".orders-bar-fixed .btn").map { |node| node.text.strip }
      assert_equal [ "Cancel", "Save", "Send back for approval" ], labels
      assert_select ".orders-bar-fixed a.btn-secondary[href=?]:not([data-action])", orders_request_path(order_request), "Cancel"
    end
  end
end
