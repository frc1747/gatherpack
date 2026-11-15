require "test_helper"
require "support/orders_world"

# The decision slot on a request's page (spec §3.3, §3.12 approver).
class Orders::RequestDecisionTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "an approver sees the flags, the funding picture and the three buttons" do
    with_orders(@world) do
      budget = FundingSource.create!(team: @world.robotics, name: "Build budget", amount_cents: 5_000)
      order_request = submitted_request(@world, lines: [ { description: "Mystery part" } ])
      order_request.update!(funding_source: budget)
      sign_in @world.mentor.user

      get orders_request_url(order_request)

      assert_select "#decision" do
        assert_select "h2", /Approval/
        assert_select ".orders-decision-flags", /Store not chosen/
        assert_select ".orders-decision-flags", /No link or part number/
        assert_select ".orders-decision-flags", /No price/
        assert_select ".orders-decision-funding", /Build budget/
        assert_select ".orders-decision-funding", /Left after this request/
        assert_select ".orders-decision-bar button[value=approved]", "Approve"
        assert_select ".orders-decision-bar button[value=changes_requested]", "Ask for changes"
        assert_select ".orders-decision-bar button[value=declined]", "Decline"
        assert_select "details.orders-line-edit", 1
        assert_select "input[name=fits_restriction]", 0
        assert_select "select[name=funding_source_id]", 0
      end
      assert_select "link[href*=orders_decision]"
    end
  end

  test "a restricted source shows its restriction and the tick Approve needs" do
    with_orders(@world) do
      grant = FundingSource.create!(team: @world.robotics, name: "Parts grant", kind: :restricted, restriction: "Robot parts only")
      order_request = submitted_request(@world)
      order_request.update!(funding_source: grant)
      sign_in @world.mentor.user

      get orders_request_url(order_request)

      assert_select ".orders-decision-funding", /Robot parts only/
      assert_select ".orders-decision-bar input[type=checkbox][name=fits_restriction][required]"
      assert_select ".orders-decision-bar label", /This request fits the restriction of Parts grant/
      assert_select "button[value=declined][formnovalidate]"
    end
  end

  test "a request with no funding source shows the picker with the sources its team can use" do
    with_orders(@world) do
      FundingSource.create!(team: @world.club, name: "Club budget")
      FundingSource.create!(team: @world.art, name: "Art budget")
      order_request = submitted_request(@world)
      sign_in @world.mentor.user

      get orders_request_url(order_request)

      assert_select "select[name=funding_source_id]" do
        assert_select "option", text: "Club budget"
        assert_select "option", text: "Art budget", count: 0
      end
      assert_select ".orders-decision-flags", /No funding source/
    end
  end

  test "an approver who made the request, or is related to who did, is told why the buttons are missing" do
    with_orders(@world) do
      own = submitted_request(@world, by: @world.mentor)
      relative = submitted_request(@world)

      sign_in @world.mentor.user
      get orders_request_url(own)
      assert_select "#decision", /You made this request, so another approver has to decide./
      assert_select ".orders-decision-bar", 0

      sign_in @world.parent.user
      get orders_request_url(relative)
      assert_select "#decision", /A relative made this request, so another approver has to decide./
      assert_select ".orders-decision-bar", 0
    end
  end

  test "people who don't approve for the team see no decision" do
    with_orders(@world) do
      order_request = submitted_request(@world)

      [ @world.requester, @world.teammate ].each do |person|
        sign_in person.user
        get orders_request_url(order_request)
        assert_response :success
        assert_select "#decision", 0
      end
    end
  end

  test "the next step's approvers see the step and the approvals so far" do
    with_settings(two_step_settings(@world, minimum: 5)) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Kit", price: 10 } ])
      order_request.decide!(:approved, by: @world.mentor)
      sign_in @world.manager.user

      get orders_request_url(order_request)

      assert_select "#decision h2", /Treasurer/
      assert_select "#decision h2", /step 2 of 2/
      assert_select "#decision", /Mentor:\s+approved by #{@world.mentor.identifier_name}/
      assert_select ".orders-decision-bar button[value=approved]"
    end
  end

  test "re-approval lists the changed items, with no Ask for changes and no item edits" do
    with_settings(orders_settings(@world, orders_price_tolerance: "10%, 25")) do
      Orders::Current.reset
      order_request = approved_request(@world, lines: [ { description: "Kit", price: 100 } ])
      buy(@world, order_request.order_lines.to_a, prices: { order_request.order_lines.first.id => 13_000 })
      sign_in @world.mentor.user

      get orders_request_url(order_request)

      assert_select "#decision h2", /Re-approve changed items/
      assert_select "#decision li", /Kit × 1/
      assert_select "button[value=approved]"
      assert_select "button[value=declined]"
      assert_select "button[value=changes_requested]", 0
      assert_select "details.orders-line-edit", 0
    end
  end

  test "nothing shows once the request is decided" do
    with_orders(@world) do
      order_request = approved_request(@world)
      sign_in @world.mentor.user

      get orders_request_url(order_request)

      assert_select "#decision", 0
    end
  end
end
