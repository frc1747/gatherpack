require "test_helper"
require "support/orders_world"

class Orders::ReallocationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup do
    @world = build_orders_world
    @from = FundingSource.create!(team: @world.robotics, name: "Operating")
    @to = FundingSource.create!(team: @world.robotics, name: "Grant", kind: :restricted, restriction: "Parts")
  end

  def bought_line
    request = approved_request(@world, funding_source: @from)
    buy(@world, request.order_lines, vendor: @world.preferred_vendor)
    [ request, request.order_lines.first.reload ]
  end

  test "a funding manager moves a bought line with a reason, and it lands in the timeline" do
    with_orders(@world) do
      request, line = bought_line
      sign_in @world.funding_manager.user

      post reallocate_orders_request_line_url(request, line), params: { funding_source_id: @to.id, reason: "Grant covers parts" }
      assert_redirected_to orders_request_url(request)
      assert_equal @to, line.reload.effective_funding_source
      event = request.events.last
      assert_equal "Grant covers parts", event.comment
      assert_equal [ "Operating", "Grant" ], event.field_changes["funding_source"]
    end
  end

  test "a reason is required" do
    with_orders(@world) do
      request, line = bought_line
      sign_in @world.funding_manager.user

      post reallocate_orders_request_line_url(request, line), params: { funding_source_id: @to.id, reason: "" }
      assert_match "reason", flash[:alert]
      assert_equal @from, line.reload.effective_funding_source
    end
  end

  test "a line that isn't bought yet can't be moved" do
    with_orders(@world) do
      request = approved_request(@world, funding_source: @from)
      line = request.order_lines.first
      sign_in @world.funding_manager.user

      post reallocate_orders_request_line_url(request, line), params: { funding_source_id: @to.id, reason: "Early" }
      assert_match "Only a bought item", flash[:alert]
    end
  end

  test "an unknown funding source is refused and the line stays put" do
    with_orders(@world) do
      request, line = bought_line
      sign_in @world.funding_manager.user

      [ "no-such-source", SecureRandom.uuid ].each do |id|
        post reallocate_orders_request_line_url(request, line), params: { funding_source_id: id, reason: "Typo" }
        assert_match "wasn't found", flash[:alert]
      end
      assert_equal @from, line.reload.effective_funding_source
      assert_not request.events.exists?(comment: "Typo")
    end
  end

  test "a blank source puts the line back on the request's, and says so" do
    with_orders(@world) do
      request, line = bought_line
      line.update!(funding_source: @to)
      sign_in @world.funding_manager.user

      post reallocate_orders_request_line_url(request, line), params: { funding_source_id: "", reason: "Back to the request" }
      assert_match "request's funding source", flash[:notice]
      assert_equal @from, line.reload.effective_funding_source
    end
  end

  test "approvers, buyers and requesters can't move a line" do
    with_orders(@world) do
      request, line = bought_line
      [ @world.mentor, @world.buyer, @world.requester ].each do |person|
        sign_in person.user
        post reallocate_orders_request_line_url(request, line), params: { funding_source_id: @to.id, reason: "Nope" }
        assert_redirected_to root_url
      end
      assert_equal @from, line.reload.effective_funding_source
    end
  end

  test "a source the request's team can't use is refused with a message" do
    with_orders(@world) do
      request, line = bought_line
      other = FundingSource.create!(team: @world.art, name: "Art Fund")
      sign_in @world.admin.user

      post reallocate_orders_request_line_url(request, line), params: { funding_source_id: other.id, reason: "Try" }
      assert_response :see_other
      assert flash[:alert].present?
      assert_equal @from, line.reload.effective_funding_source
    end
  end
end
