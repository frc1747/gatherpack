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
        # Any text a requester typed as a link must not stop the form saving.
        assert_select "input[name='line[url]'][type=text][inputmode=url]"
        assert_select "p", /Changing what an item is, where it's from, its link, part numbers or unit/
        assert_select "input[name=fits_restriction]", 0
        assert_select "select[name=funding_source_id]", 0
      end
      # Not tracked, or Turbo would reload the page on every visit.
      assert_select "link[href*=orders_decision]:not([data-turbo-track])"
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

  test "every item's fix form has its own field ids, so a label reaches its own box" do
    with_orders(@world) do
      order_request = submitted_request(@world, lines: [ { description: "Gear", price: 10 }, { description: "Belt", price: 5 } ])
      sign_in @world.mentor.user

      get orders_request_url(order_request)

      forms = css_select("details.orders-line-edit form")
      assert_equal 2, forms.size
      label_targets = forms.map { |form| form.css("label").filter_map { |label| label["for"] } }
      assert_empty label_targets.first & label_targets.last
      forms.each do |form|
        ids = form.css("[id]").map { |node| node["id"] }
        label_targets_in_form = form.css("label").filter_map { |label| label["for"] }
        assert_empty label_targets_in_form - ids, "each label points at a field in its own form"
      end
      all_ids = css_select("details.orders-line-edit [id]").map { |node| node["id"] }
      assert_equal all_ids.uniq, all_ids
    end
  end

  test "the comment box says when a comment is needed, on a re-approval too" do
    with_settings(orders_settings(@world, orders_price_tolerance: "10%, 25")) do
      Orders::Current.reset
      first = submitted_request(@world)
      reapproval = approved_request(@world, lines: [ { description: "Kit", price: 100 } ])
      buy(@world, reapproval.order_lines.to_a, prices: { reapproval.order_lines.first.id => 13_000 })
      sign_in @world.mentor.user

      [ first, reapproval ].each do |order_request|
        get orders_request_url(order_request)

        assert_select "#decision textarea[placeholder='Comment (needed to ask for changes or decline)']"
      end
    end
  end

  test "re-approval shows the approved total, the new one and the rise, with no $0.00 for this request" do
    with_settings(orders_settings(@world, orders_price_tolerance: "10%, 25")) do
      Orders::Current.reset
      budget = FundingSource.create!(team: @world.robotics, name: "Build budget", amount_cents: 100_000)
      order_request = approved_request(@world, lines: [ { description: "Kit", price: 100 } ], funding_source: budget)
      buy(@world, order_request.order_lines.to_a, prices: { order_request.order_lines.first.id => 13_000 })
      sign_in @world.mentor.user

      get orders_request_url(order_request)

      assert_select "#decision p", text: "Approved $100.00, now $130.00 (+$30.00)"
      assert_select ".orders-decision-funding dt", text: "This request", count: 0
      assert_select ".orders-decision-funding dt", text: "Left, with these items"
      assert_select ".orders-decision-funding dd", text: "$870.00"
    end
  end

  test "the items of a declined request say it was declined, not that they're waiting" do
    with_orders(@world) do
      order_request = submitted_request(@world, lines: [ { description: "Gear", price: 10 }, { description: "Belt", price: 5 } ])
      order_request.decide!(:declined, by: @world.mentor, comment: "Not this term")
      sign_in @world.requester.user

      get orders_request_url(order_request)

      assert_select "#items .badge", text: "Declined", count: 2
      assert_select "#items .badge", text: "Waiting for approval", count: 0
    end
  end

  test "items of a request waiting for approval still say so" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.requester.user

      get orders_request_url(order_request)

      assert_select "#items .badge", text: "Waiting for approval"
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
