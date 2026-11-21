require "test_helper"
require "json"

class ShareTargetTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @settings_store = Settings.instance.store
    @settings_file = Tempfile.new([ "settings", ".pstore" ])
    Settings.instance.store = PStore.new(@settings_file.path, true)
    Settings.set(:feature_installable_app, "true")
    @registrations = GatherPack::ShareActions.snapshot
    GatherPack::ShareActions.restore({})
    @user = User.create!(email: "sharer@example.com", password: "Password1!")
    Person.create!(user: @user, first_name: "Sam", last_name: "Sharer")
  end

  teardown do
    GatherPack::ShareActions.restore(@registrations)
    Settings.instance.store = @settings_store
    @settings_file.close!
  end

  test "manifest declares a GET share target with the flag on" do
    get "/manifest.json"
    target = JSON.parse(response.body)["share_target"]

    assert_equal "/share", target["action"]
    assert_equal "GET", target["method"]
    assert_equal({ "url" => "url", "text" => "text", "title" => "title" }, target["params"])
  end

  test "manifest has no share target with the flag off" do
    Settings.set(:feature_installable_app, "false")
    get "/manifest.json"
    assert_not JSON.parse(response.body).key?("share_target")
  end

  test "signed-out people are sent to sign in" do
    get "/share", params: { url: "https://example.com" }
    assert_redirected_to new_user_session_path
  end

  test "is not found with the flag off" do
    sign_in @user
    Settings.set(:feature_installable_app, "false")
    get "/share"
    assert_response :not_found
  end

  test "says so when nothing can use the link" do
    sign_in @user
    get "/share", params: { url: "https://example.com" }
    assert_response :success
    assert_includes response.body, "Nothing here can use a shared link"
  end

  test "one visible action redirects with the url found in the text" do
    GatherPack::ShareActions.register(:keep, label: "Keep it", path: ->(shared) { "/keep?u=#{CGI.escape(shared.url.to_s)}" })
    sign_in @user
    get "/share", params: { text: "neat https://example.com/a" }
    assert_redirected_to "/keep?u=#{CGI.escape("https://example.com/a")}"
  end

  test "several visible actions show a picker and hidden ones are left out" do
    GatherPack::ShareActions.register(:keep, label: "Keep it", path: ->(_) { "/keep" })
    GatherPack::ShareActions.register(:toss, label: "Toss it", path: ->(_) { "/toss" })
    GatherPack::ShareActions.register(:secret, label: "Secret", path: ->(_) { "/secret" }, visible: ->(_) { false })
    sign_in @user
    get "/share", params: { url: "https://example.com" }

    assert_response :success
    assert_select "a[href='/keep']", "Keep it"
    assert_select "a[href='/toss']", "Toss it"
    assert_select "a", text: "Secret", count: 0
  end

  test "the page has a breadcrumb back to Home when nothing can use the link" do
    sign_in @user
    get "/share", params: { url: "https://example.com" }

    assert_select ".breadcrumb a[href=?]", root_path, text: "Home"
    assert_select ".breadcrumb", text: /Share/
  end

  test "the page has a breadcrumb back to Home beside its share actions" do
    GatherPack::ShareActions.register(:keep, label: "Keep it", path: ->(_) { "/keep" })
    GatherPack::ShareActions.register(:toss, label: "Toss it", path: ->(_) { "/toss" })
    sign_in @user
    get "/share", params: { url: "https://example.com" }

    assert_select ".breadcrumb a[href=?]", root_path, text: "Home"
    assert_select ".breadcrumb", text: /Share/
    assert_select ".card a.btn.btn-primary.btn-lg", count: 2
  end

  test "the page verifies authorization" do
    assert ShareController <= InternalController
    assert SharePolicy.new(@user, :share).show?
    assert_not SharePolicy.new(nil, :share).show?
  end
end
