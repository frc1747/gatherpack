require "test_helper"
require "support/orders_world"

class Orders::LineEditsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  # The form as the decision slot posts it: every box, with the line's
  # current values unless changed.
  def form_values(line, **changes)
    {
      description: line.description, manufacturer: line.manufacturer, manufacturer_part_number: line.manufacturer_part_number,
      vendor_part_number: line.vendor_part_number, url: line.url, unit: line.unit, units_per: line.units_per,
      quantity: line.quantity, estimated_unit_price: line.estimated_unit_price&.to_s,
      store: line.vendor_id || (line.other_vendor_name.present? ? "other" : ""),
      other_vendor_name: line.other_vendor_name, other_vendor_reason: line.other_vendor_reason, note: line.note
    }.merge(changes)
  end

  test "an approver lowers a quantity and adds a note; it's in the timeline and approvals stand" do
    with_settings(two_step_settings(@world, minimum: 5)) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Bolt", quantity: 10, price: 1, vendor_id: @world.preferred_vendor.id } ])
      order_request.decide!(:approved, by: @world.mentor)
      line = order_request.order_lines.first
      sign_in @world.admin.user

      patch orders_request_line_edit_url(order_request, line), params: { line: form_values(line, quantity: "4", note: "Four is plenty") }

      assert_redirected_to orders_request_url(order_request, anchor: "decision")
      line.reload
      assert_equal 4, line.quantity
      assert_equal "Four is plenty", line.note
      event = order_request.events.last
      assert_equal "edited", event.action
      assert_equal @world.admin, event.actor
      assert_equal [ 10, 4 ], event.field_changes["quantity"]
      assert_equal 1, order_request.reload.active_approvals.count(&:approved?), "lowering a quantity doesn't clear approvals"
    end
  end

  test "changing an item's store or part number clears earlier approvals" do
    with_settings(two_step_settings(@world, minimum: 5)) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Bolt", quantity: 10, price: 1 } ])
      order_request.decide!(:approved, by: @world.mentor)
      line = order_request.order_lines.first
      sign_in @world.admin.user

      patch orders_request_line_edit_url(order_request, line), params: { line: form_values(line, store: @world.other_vendor.id) }

      assert_equal @world.other_vendor, line.reload.vendor
      assert_empty order_request.reload.active_approvals
      assert_equal "mentor", order_request.current_step.key

      order_request.decide!(:approved, by: @world.mentor)
      patch orders_request_line_edit_url(order_request, line), params: { line: form_values(line.reload, vendor_part_number: "B-10") }

      assert_equal "B-10", line.reload.vendor_part_number
      assert_empty order_request.reload.active_approvals
    end
  end

  test "an approver sets a price, another store and the item's own funding source" do
    with_orders(@world) do
      grant = FundingSource.create!(team: @world.robotics, name: "Tools grant")
      order_request = submitted_request(@world, lines: [ { description: "Saw" } ])
      line = order_request.order_lines.first
      sign_in @world.mentor.user

      patch orders_request_line_edit_url(order_request, line),
        params: { line: form_values(line, estimated_unit_price: "$1,234.50", store: "other", other_vendor_name: "Tool Town", funding_source_id: grant.id) }

      line.reload
      assert_equal 123_450, line.estimated_unit_price_cents
      assert_equal "Tool Town", line.other_vendor_name
      assert_equal grant, line.funding_source
    end
  end

  test "outer spaces on a stored value don't count as a change, so fixing the price keeps step 1's approval" do
    with_settings(two_step_settings(@world, minimum: 5)) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Wheel ", url: " https://partsdepot.example/p/W-1 ", quantity: 4, price: 10 } ])
      order_request.decide!(:approved, by: @world.mentor)
      line = order_request.order_lines.first
      sign_in @world.manager.user

      patch orders_request_line_edit_url(order_request, line),
        params: { line: form_values(line, description: "Wheel", url: "https://partsdepot.example/p/W-1", estimated_unit_price: "9.50") }

      line.reload
      assert_equal 950, line.estimated_unit_price_cents
      assert_equal "Wheel ", line.description, "an unchanged box isn't written back"
      assert_equal [ "estimated_unit_price_cents" ], order_request.events.last.field_changes.keys
      assert_equal 1, order_request.reload.active_approvals.count(&:approved?)
    end
  end

  test "posting the form unchanged records nothing" do
    with_orders(@world) do
      order_request = submitted_request(@world, lines: [ { description: "Saw", price: 5 } ])
      line = order_request.order_lines.first
      sign_in @world.mentor.user

      assert_no_difference -> { order_request.events.count } do
        patch orders_request_line_edit_url(order_request, line), params: { line: form_values(line) }
      end
    end
  end

  test "a price that isn't a number, or a quantity of nothing, is refused with a message" do
    with_orders(@world) do
      order_request = submitted_request(@world, lines: [ { description: "Saw", price: 5 } ])
      line = order_request.order_lines.first
      sign_in @world.mentor.user

      patch orders_request_line_edit_url(order_request, line), params: { line: form_values(line, estimated_unit_price: "cheap") }
      assert_equal "Enter the price as a number, like 12.50.", flash[:alert]

      patch orders_request_line_edit_url(order_request, line), params: { line: form_values(line, quantity: "0") }
      assert_match "Quantity", flash[:alert]
      assert_equal 1, line.reload.quantity
    end
  end

  test "only an approver who can decide edits items here" do
    with_orders(@world) do
      order_request = submitted_request(@world, lines: [ { description: "Saw", price: 5 } ])
      line = order_request.order_lines.first

      [ @world.requester, @world.parent, @world.teammate ].each do |person|
        sign_in person.user
        patch orders_request_line_edit_url(order_request, line), params: { line: form_values(line, quantity: "9") }
        assert_equal "You are not allowed to do that", flash[:notice], person.first_name
      end
      assert_equal 1, line.reload.quantity
    end
  end

  test "items can't be edited here once the request is approved" do
    with_orders(@world) do
      order_request = approved_request(@world)
      line = order_request.order_lines.first
      sign_in @world.admin.user

      patch orders_request_line_edit_url(order_request, line), params: { line: form_values(line, quantity: "9") }

      assert_equal "You are not allowed to do that", flash[:notice]
      assert_equal 1, line.reload.quantity
    end
  end
end
