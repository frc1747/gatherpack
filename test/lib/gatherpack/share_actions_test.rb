require "test_helper"

class ShareActionsTest < ActiveSupport::TestCase
  setup { @registrations = GatherPack::ShareActions.snapshot }
  teardown { GatherPack::ShareActions.restore(@registrations) }

  def shared(**params)
    GatherPack::ShareActions.shared_from(ActionController::Parameters.new(params))
  end

  test "uses the url parameter" do
    assert_equal "https://example.com/a?b=1", shared(url: "https://example.com/a?b=1").url
  end

  test "finds the link inside shared text" do
    result = shared(text: "Look at this: https://example.com/item/9.", title: "Cool")
    assert_equal "https://example.com/item/9", result.url
    assert_equal "Cool", result.title
  end

  test "finds the link inside the title when text has none" do
    assert_equal "http://example.com/x", shared(text: "hello", title: "see http://example.com/x").url
  end

  test "ignores a url parameter that is not a web link" do
    assert_nil shared(url: "javascript:alert(1)").url
  end

  test "has no url when nothing looks like one" do
    result = shared(text: "just words")
    assert_nil result.url
    assert_equal "just words", result.text
  end

  test "only offers visible actions and replaces a key registered twice" do
    GatherPack::ShareActions.restore({})
    GatherPack::ShareActions.register(:one, label: "One", path: ->(_) { "/one" })
    GatherPack::ShareActions.register(:two, label: "Two", path: ->(_) { "/two" }, visible: ->(user) { user == :yes })
    GatherPack::ShareActions.register(:one, label: "Uno", path: ->(_) { "/uno" })

    assert_equal [ "Uno" ], GatherPack::ShareActions.visible_for(:no).map(&:label)
    assert_equal [ "Uno", "Two" ], GatherPack::ShareActions.visible_for(:yes).map(&:label)
  end

  test "keeps a closing bracket that closes one in the link" do
    assert_equal "https://example.com/Bolt_(fastener)", shared(text: "see https://example.com/Bolt_(fastener)").url
    assert_equal "https://example.com/a", shared(text: "(see https://example.com/a)").url
    assert_equal "https://example.com/a", shared(text: "see https://example.com/a).").url
  end

  test "uses the url parameter exactly as sent" do
    assert_equal "https://example.com/a_(b).", shared(url: "https://example.com/a_(b).").url
    assert_equal "https://example.com/a)", shared(url: "https://example.com/a)").url
  end

  test "path_for only accepts a path within the app" do
    shared_link = shared(url: "https://example.com")
    {
      "/orders/new" => true, "https://evil.example/" => false, "//evil.example/" => false, "orders" => false
    }.each do |path, ok|
      action = GatherPack::ShareActions::Action.new(key: :x, label: "X", path: ->(_) { path })
      if ok
        assert_equal path, GatherPack::ShareActions.path_for(action, shared_link)
      else
        assert_raises(ArgumentError) { GatherPack::ShareActions.path_for(action, shared_link) }
      end
    end
  end
end
