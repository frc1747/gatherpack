require "test_helper"

class VersionHelperTest < ActionView::TestCase
  teardown do
    ENV.delete("GATHERPACK_VERSION")
    ENV.delete("GATHERPACK_REVISION")
  end

  test "gatherpack_version reads GATHERPACK_VERSION and drops a leading v" do
    ENV["GATHERPACK_VERSION"] = "v1.2.3-rc.1"
    assert_equal "1.2.3-rc.1", gatherpack_version

    ENV["GATHERPACK_VERSION"] = "main"
    assert_equal "main", gatherpack_version
  end

  test "gatherpack_version is nil when unset outside development" do
    assert_nil gatherpack_version
  end

  test "gatherpack_revision shortens the commit" do
    ENV["GATHERPACK_REVISION"] = "34087a3f0e1c2d3b4a5968778695a4b3c2d1e0f9"
    assert_equal "34087a3", gatherpack_revision
  end
end
