require "test_helper"
require_relative "../support/settings_test_helper"

# The widget screens follow the screen standard: a secondary Cancel,
# tables that scroll on phones, and Delete asking with its effect.
class WidgetsScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SettingsTestHelper

  setup do
    host! "localhost"
    @admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
    @widget = Widget.create!(title: "Shop hours", placement: "left")
  end

  test "the index table scrolls on phones and the footer has New Widget" do
    with_feature do
      sign_in @admin
      get widgets_path

      assert_select ".table-responsive tr##{ActionView::RecordIdentifier.dom_id(@widget)}"
      assert_select ".card-footer a.btn-success[href=?]", new_widget_path, text: "New Widget"
    end
  end

  test "the new form cancels with a secondary button and saves" do
    with_feature do
      sign_in @admin
      get new_widget_path
      assert_select "a.btn-secondary[href=?]", widgets_path, text: "Cancel"
      assert_select "a.btn-warning", count: 0

      post widgets_path, params: { widget: { title: "Notes", content: "Hello", placement: "top", position: 1, viewer: "user" } }
      assert_redirected_to widget_path(Widget.find_by!(title: "Notes"))
    end
  end

  test "the edit form cancels with a secondary button and saves" do
    with_feature do
      sign_in @admin
      get edit_widget_path(@widget)
      assert_select "a.btn-secondary[href=?]", widget_path(@widget), text: "Cancel"

      patch widget_path(@widget), params: { widget: { title: "Opening hours" } }
      assert_redirected_to widget_path(@widget)
      assert_equal "Opening hours", @widget.reload.title
    end
  end

  test "the widget page has Edit and a Delete that names its effect" do
    with_feature do
      sign_in @admin
      get widget_path(@widget)

      assert_select ".card-footer a.btn-warning[href=?]", edit_widget_path(@widget), text: "Edit"
      assert_select ".card-footer form[action=?][data-turbo-confirm*='Delete Shop hours?'] button.btn-danger", widget_path(@widget), text: "Delete"

      assert_difference -> { Widget.count }, -1 do
        delete widget_path(@widget)
      end
    end
  end

  private

  def with_feature(&block)
    with_settings(feature_widgets: "true", &block)
  end
end
