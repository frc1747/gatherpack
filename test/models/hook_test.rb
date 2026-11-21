require "test_helper"

class HookTest < ActiveSupport::TestCase
  setup do
    @targets = GatherPack::HookCatalog.targets.dup
    @events = GatherPack::HookCatalog.events.dup
  end

  teardown do
    GatherPack::HookCatalog.reset!
    GatherPack::HookCatalog.register_targets(@targets)
    GatherPack::HookCatalog.register_events(@events)
  end

  test "catalog lists built-in events" do
    assert_includes Hook.catalog, "people - create"
    assert_includes Hook.catalog, "token - activate"
  end

  test "catalog includes registered targets and events" do
    GatherPack::HookCatalog.register_targets("widgets")
    GatherPack::HookCatalog.register_events("widgets - published")

    catalog = Hook.catalog
    assert_includes catalog, "widgets - create"
    assert_includes catalog, "widgets - update"
    assert_includes catalog, "widgets - destroy"
    assert_includes catalog, "widgets - published"
    assert_equal catalog.sort, catalog
  end

  test "registering twice lists an event once" do
    2.times { GatherPack::HookCatalog.register_targets("widgets") }

    assert_equal 1, Hook.catalog.count("widgets - create")
  end
end
