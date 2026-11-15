require "test_helper"

class Mcp::SettingsStoreTest < ActiveSupport::TestCase
  # Mcp::Access reads the store on every request; overlapping requests must
  # wait for each other rather than raise "nested transaction".
  test "the settings store is thread safe" do
    assert Settings.instance.store.instance_variable_get(:@thread_safe)
  end
end
