require "test_helper"
require "support/orders_world"

class Orders::ShareActionTest < ActiveSupport::TestCase
  include OrdersWorld

  # Where the share seam isn't merged in, stand in for it. Where it is, use the
  # real registry and put its registrations back afterwards.
  StubShareActions = Module.new do
    Action = Struct.new(:key, :label, :visible, :path, keyword_init: true)

    def self.actions = (@actions ||= {})

    def self.register(key, label:, path:, visible: nil)
      actions[key] = Action.new(key: key, label: label, visible: visible, path: path)
    end

    def self.snapshot = actions.dup

    def self.restore(snapshot)
      @actions = snapshot.dup
    end
  end

  setup do
    @world = build_orders_world
    @real_seam = GatherPack.const_get(:ShareActions, false) if GatherPack.const_defined?(:ShareActions, false)
    if @real_seam
      @registrations = @real_seam.snapshot
    else
      GatherPack.const_set(:ShareActions, StubShareActions)
      StubShareActions.restore({})
    end
  end

  teardown do
    if @real_seam
      GatherPack.send(:remove_const, :ShareActions) unless GatherPack::ShareActions.equal?(@real_seam)
      GatherPack.const_set(:ShareActions, @real_seam) unless GatherPack.const_defined?(:ShareActions, false)
      @real_seam.restore(@registrations)
    else
      GatherPack.send(:remove_const, :ShareActions)
    end
  end

  test "registers one action when the seam exists" do
    Orders::ShareAction.register

    assert_equal "Ask to buy this", GatherPack::ShareActions.snapshot.fetch(:orders_request).label
  end

  test "registers nothing without the seam" do
    GatherPack.send(:remove_const, :ShareActions)
    begin
      assert_nothing_raised { Orders::ShareAction.register }
    ensure
      GatherPack.const_set(:ShareActions, @real_seam || StubShareActions)
    end
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
