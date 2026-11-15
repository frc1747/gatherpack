require "test_helper"
require "support/orders_world"

class Orders::ShareActionTest < ActiveSupport::TestCase
  include OrdersWorld

  # This branch doesn't contain the share seam, so stand in for it.
  StubShareActions = Module.new do
    def self.actions = (@actions ||= {})

    def self.register(key, label:, path:, visible: nil)
      actions[key] = { label: label, path: path, visible: visible }
    end
  end

  setup do
    @world = build_orders_world
    @had_seam = GatherPack.const_defined?(:ShareActions, false)
    GatherPack.const_set(:ShareActions, StubShareActions) unless @had_seam
    StubShareActions.actions.clear
  end

  teardown do
    GatherPack.send(:remove_const, :ShareActions) unless @had_seam
  end

  test "registers one action when the seam exists" do
    Orders::ShareAction.register

    action = StubShareActions.actions.fetch(:orders_request)
    assert_equal "Ask to buy this", action[:label]
  end

  test "registers nothing without the seam" do
    GatherPack.send(:remove_const, :ShareActions)
    assert_nothing_raised { Orders::ShareAction.register }
    GatherPack.const_set(:ShareActions, StubShareActions)
  end

  test "visible to a requester while orders is on" do
    with_orders(@world) do
      assert Orders::ShareAction.visible?(@world.requester.user)
    end
  end

  test "hidden while orders is off" do
    with_orders(@world, feature_orders: "false") do
      assert_not Orders::ShareAction.visible?(@world.requester.user)
    end
  end

  test "hidden from someone who may not request" do
    with_orders(@world, orders_requesters: @world.robotics.name) do
      assert_not Orders::ShareAction.visible?(@world.outsider.user)
      assert Orders::ShareAction.visible?(@world.requester.user)
    end
  end

  test "hidden when nobody is signed in" do
    with_orders(@world) do
      assert_not Orders::ShareAction.visible?(nil)
    end
  end

  test "path carries the shared link, URL-encoded" do
    shared = Struct.new(:url).new("https://partsdepot.example/p/AB-1?a=1&b=two words")

    assert_equal "/orders/requests/new?url=https%3A%2F%2Fpartsdepot.example%2Fp%2FAB-1%3Fa%3D1%26b%3Dtwo+words",
      Orders::ShareAction.path(shared)
  end

  test "path without a link opens the blank form" do
    assert_equal "/orders/requests/new", Orders::ShareAction.path(Struct.new(:url).new(nil))
  end
end
