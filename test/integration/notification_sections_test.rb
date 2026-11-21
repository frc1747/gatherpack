require "test_helper"
require "phone_notifications_test_support"

class NotificationSectionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PhoneNotificationsTestSupport

  setup do
    host! "localhost"
    use_throwaway_settings
    @views = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@views, "notification_test"))
    File.write(File.join(@views, "notification_test", "_card.html.erb"), %(<div class="card" id="test-card"><h2>Email</h2></div>))
    ActionController::Base.prepend_view_path(@views)
    @user = users(:one)
    sign_in @user
  end

  teardown do
    GatherPack::NotificationSections.unregister(:test_card)
    ActionController::Base.view_paths = ActionController::Base.view_paths.reject { |path| path.to_s == @views }
    FileUtils.remove_entry(@views)
    restore_settings
  end

  def register_card(visible: ->(_user) { true })
    GatherPack::NotificationSections.register(:test_card, partial: "notification_test/card", visible: visible)
  end

  test "with phone notifications off, a visible section opens the page on its own" do
    set_push_flag(false)
    register_card

    get notifications_path

    assert_response :success
    assert_select "h1", "Notifications"
    assert_select ".card > .card-header h1", "Notifications"
    assert_select "#test-card"
    assert_select "input#push_this_device", false
    assert_select "[data-controller='push-notifications']", false
  end

  test "with phone notifications off, the sidebar links the page without the device sync" do
    set_push_flag(false)
    register_card

    get root_path

    assert_select "a[href=?]", notifications_path
    assert_select "[data-controller='push-sync']", false
  end

  test "a section that isn't visible to the person leaves the page closed" do
    set_push_flag(false)
    register_card(visible: ->(_user) { false })

    get notifications_path

    assert_redirected_to root_path
  end

  test "with phone notifications on, sections come after the phone cards" do
    set_push_flag(true)
    create_push_gateway
    register_card

    get notifications_path

    assert_response :success
    assert_select "input#push_this_device"
    assert_match(/Tell me about.*test-card/m, response.body)
  end

  test "impersonating can't open the page through a section" do
    set_push_flag(false)
    register_card
    @user.update_columns(admin: true)
    post impersonate_person_path(users(:two).person)

    get notifications_path

    assert_redirected_to root_path
  end
end
