require "test_helper"
require "support/orders_world"

class FundingSourcePolicyTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  def policy(person, record)
    Orders::Current.reset
    FundingSourcePolicy.new(person.user, record)
  end

  test "funding managers, team managers and admins manage sources within reach" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.robotics, name: "Build budget")
      art = FundingSource.create!(team: @world.art, name: "Art budget")

      assert policy(@world.funding_manager, source).update?
      assert_not policy(@world.funding_manager, art).update?
      assert policy(@world.manager, source).update?
      assert policy(@world.admin, art).update?
      assert_not policy(@world.buyer, source).update?, "buyers can't without the grant"
      assert_not policy(@world.mentor, source).update?, "approvers can't without the grant"
      assert_not policy(@world.requester, FundingSource).create?
      assert policy(@world.funding_manager, FundingSource).create?
    end
  end

  test "restricted fields are for funding managers, approvers and admins" do
    with_orders(@world) do
      grant = FundingSource.create!(team: @world.robotics, name: "Grant", kind: :restricted, restriction: "Parts", giver: "A foundation")

      assert policy(@world.requester, grant).show?
      assert_not policy(@world.requester, grant).restricted_fields?
      assert_not policy(@world.buyer, grant).restricted_fields?
      assert policy(@world.mentor, grant).restricted_fields?
      assert policy(@world.funding_manager, grant).restricted_fields?
      assert policy(@world.admin, grant).restricted_fields?
    end
  end
end
