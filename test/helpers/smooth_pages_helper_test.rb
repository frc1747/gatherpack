require "test_helper"

class SmoothPagesHelperTest < ActionView::TestCase
  test "a view can opt in to morph itself" do
    assert_not smooth_refresh?

    content_for(:smooth_refresh, true)

    assert smooth_refresh?
  end
end
