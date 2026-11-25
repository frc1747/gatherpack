require "test_helper"
require "support/orders_world"

# A buyer's line actions on To buy and an order's page sit in a small More
# per line (BL-069); each still works, and Cancel item asks first.
class Orders::LineActionsMoreTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  # The line's More: its summary and each form's action, submit and confirm.
  def line_more(line)
    more = css_select("##{ActionView::RecordIdentifier.dom_id(line)} details.orders-line-actions").sole
    summary = more.at_css("> summary")
    forms = more.css("form").to_h do |form|
      submit = form.at_css("input[type=submit]")
      [ submit["value"], { action: form["action"], classes: submit["class"], confirm: form["data-turbo-confirm"] } ]
    end
    [ summary, forms ]
  end

  test "on To buy each line's actions are in a small More, and each still works" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Gear", price: 10, quantity: 4 }, { description: "Belt", price: 5 } ])
      gear, belt = order_request.order_lines.to_a
      sign_in @world.buyer.user

      get to_buy_orders_purchases_url
      assert_response :success

      summary, forms = line_more(gear)
      assert_equal "More", summary.text.strip
      assert_equal %w[btn btn-sm btn-secondary dropdown-toggle], summary["class"].split
      assert_equal [ "Change quantity", "Split", "Cancel item" ], forms.keys
      assert_equal "btn btn-secondary", forms["Change quantity"][:classes]
      assert_equal "btn btn-secondary", forms["Split"][:classes]
      assert_equal "btn btn-danger", forms["Cancel item"][:classes]
      assert_equal "Cancel Gear? It won't be bought.", forms["Cancel item"][:confirm]
      assert_select ".orders-line-actions .btn-warning", 0

      post forms["Change quantity"][:action], params: { quantity: 3 }
      assert_equal 3, gear.reload.quantity

      post forms["Split"][:action], params: { quantity_now: 1 }
      assert_equal 1, gear.reload.quantity
      assert_equal 2, order_request.order_lines.reload.count { |line| line.description == "Gear" }

      get to_buy_orders_purchases_url
      _, belt_forms = line_more(belt)
      post belt_forms["Cancel item"][:action], params: { reason: "Found one in the shop" }
      assert belt.reload.cancelled?
    end
  end

  test "on an order's page Mark delayed is in the line's More and works" do
    with_orders(@world) do
      order_request = approved_request(@world)
      line = order_request.order_lines.first
      purchase = buy(@world, [ line ], vendor: @world.preferred_vendor)
      sign_in @world.buyer.user

      get orders_purchase_url(purchase)

      summary, forms = line_more(line)
      assert_equal "More", summary.text.strip
      assert_equal [ "Mark delayed", "Change quantity", "Cancel item" ], forms.keys
      assert_equal "btn btn-secondary", forms["Mark delayed"][:classes]
      assert_equal "Cancel Gear? It won't be bought.", forms["Cancel item"][:confirm]

      post forms["Mark delayed"][:action], params: { expected_on: "2030-02-01" }
      assert line.reload.backordered?
    end
  end
end
