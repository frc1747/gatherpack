require "test_helper"
require "support/orders_world"

class Orders::ApprovalsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "To approve lists what the approver can decide, with total, team and flags" do
    with_orders(@world) do
      waiting = submitted_request(@world, title: "Wheels", needed_by: Date.current - 1,
        lines: [ { description: "Wheel", other_vendor_name: "Corner Shop", price: 12 } ])
      submitted_request(@world, title: "Mentor's own", by: @world.mentor)
      sign_in @world.mentor.user

      get orders_approvals_url

      assert_response :success
      assert_select "h1", "To approve"
      assert_select "a[href=?]", orders_request_path(waiting, anchor: "decision")
      assert_match "Wheels", response.body
      assert_match "$12.00", response.body
      assert_match @world.robotics.name, response.body
      assert_match "Other store: Corner Shop", response.body
      assert_match "No reason given", response.body
      assert_match "which has passed", response.body
      assert_no_match "Mentor&#39;s own", response.body
    end
  end

  test "To approve leaves out a relative's request and shows those needing re-approval" do
    with_settings(orders_settings(@world, orders_price_tolerance: "10%, 25")) do
      Orders::Current.reset
      submitted_request(@world, title: "Relative's")
      changed = approved_request(@world, title: "Kit", approver: @world.admin, lines: [ { description: "Kit", price: 100 } ])
      buy(@world, changed.order_lines.to_a, prices: { changed.order_lines.first.id => 13_000 })
      sign_in @world.parent.user

      get orders_approvals_url

      assert_no_match "Relative&#39;s", response.body
      assert_no_match "Needs re-approval", response.body, "the parent can't decide the requester's re-approval either"

      sign_in @world.mentor.user
      get orders_approvals_url
      assert_match "Kit", response.body
      assert_match "Needs re-approval", response.body
    end
  end

  test "someone with nothing to approve sees an empty list" do
    with_orders(@world) do
      submitted_request(@world)
      sign_in @world.requester.user

      get orders_approvals_url

      assert_response :success
      assert_match "Nothing is waiting for you to approve.", response.body
    end
  end
end
