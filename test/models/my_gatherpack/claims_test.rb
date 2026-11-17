require "test_helper"

class MyGatherpack::ClaimsTest < ActiveSupport::TestCase
  Viewer = Struct.new(:prefix) do
    def label(subject) = "#{prefix}-#{subject}"
  end

  teardown do
    MyGatherpack::Claims.unregister(:one, :form)
    MyGatherpack::Claims.unregister(:two, :form)
    MyGatherpack::Claims.unregister(:one, :page)
  end

  test "nothing is claimed until a section registers" do
    assert_empty MyGatherpack::Claims.ids(Viewer.new("v"), :form, "a")
    assert_not MyGatherpack::Claims.claimed?(Viewer.new("v"), :form, "a", "f1")
  end

  test "a registered block claims ids for a subject and runs in the view" do
    MyGatherpack::Claims.register(:one, :form) { |subject| [ label(subject) ] }

    assert MyGatherpack::Claims.claimed?(Viewer.new("v"), :form, "a", "v-a")
    assert_not MyGatherpack::Claims.claimed?(Viewer.new("v"), :form, "b", "v-a")
  end

  test "ids compare as strings and combine across sections of the same kind" do
    MyGatherpack::Claims.register(:one, :form) { |_| [ 1 ] }
    MyGatherpack::Claims.register(:two, :form) { |_| "2" }

    assert_equal Set.new(%w[1 2]), MyGatherpack::Claims.ids(Viewer.new("v"), :form, "a")
    assert MyGatherpack::Claims.claimed?(Viewer.new("v"), :form, "a", 2)
  end

  test "kinds stay apart" do
    MyGatherpack::Claims.register(:one, :page) { |_| [ "p1" ] }

    assert_not MyGatherpack::Claims.claimed?(Viewer.new("v"), :form, "a", "p1")
  end

  test "registering again replaces and unregister removes" do
    MyGatherpack::Claims.register(:one, :form) { |_| [ "old" ] }
    MyGatherpack::Claims.register(:one, :form) { |_| [ "new" ] }

    assert_equal Set.new(%w[new]), MyGatherpack::Claims.ids(Viewer.new("v"), :form, "a")

    MyGatherpack::Claims.unregister(:one, :form)
    assert_empty MyGatherpack::Claims.ids(Viewer.new("v"), :form, "a")
  end
end
