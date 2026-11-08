require "test_helper"

class PushTopicsTest < ActiveSupport::TestCase
  setup { @key = :availability_test }
  teardown { GatherPack::PushTopics.instance_variable_get(:@topics).delete(@key) }

  test "a topic with an availability check is listed only while it holds" do
    on = false
    GatherPack::PushTopics.register(@key, label: "Test", available: -> { on })

    assert_nil GatherPack::PushTopics[@key]
    assert_not_includes GatherPack::PushTopics.keys, @key
    assert_not_includes GatherPack::PushTopics.default_keys, @key

    on = true
    assert_equal "Test", GatherPack::PushTopics[@key].label
    assert_includes GatherPack::PushTopics.keys, @key
  end

  test "a topic without one is always listed" do
    GatherPack::PushTopics.register(@key, label: "Test")

    assert_includes GatherPack::PushTopics.keys, @key
  end
end
