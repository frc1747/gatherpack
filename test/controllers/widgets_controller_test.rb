require "test_helper"
require_relative "../support/settings_test_helper"

class WidgetsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SettingsTestHelper

  setup do
    host! "localhost"
    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @member = create_user("member@example.com")
    Membership.create!(person: @member.person, team: @team)
    @admin = create_user("admin@example.com", admin: true)
    @architect = create_user("architect@example.com", admin: true, architect: true)
  end

  test "widgets are off unless the feature is on" do
    with_settings(feature_widgets: "false") do
      sign_in @admin
      get widgets_path
      assert_redirected_to root_path
    end
  end

  test "members see the widgets they can see, but can't manage them" do
    with_feature do
      Widget.create!(title: "Shop hours")
      Widget.create!(title: "Den A notes", viewer: "team", team: @team)
      secret = Widget.create!(title: "Admins only", viewer: "admin")

      sign_in @member
      get widgets_path
      assert_response :success
      assert_match "Shop hours", response.body
      assert_match "Den A notes", response.body
      assert_no_match "Admins only", response.body
      assert_select "a[href=?]", new_widget_path, 0

      get widget_path(secret)
      assert_redirected_to root_path

      get new_widget_path
      assert_redirected_to root_path

      assert_no_difference -> { Widget.count } do
        post widgets_path, params: { widget: { title: "Mine" } }
      end
    end
  end

  test "an admin creates a widget" do
    with_feature do
      sign_in @admin
      get new_widget_path
      assert_response :success

      post widgets_path, params: { widget: { title: "Shop hours", content: "Open **Tuesday**", placement: "left", position: 2, viewer: "team", team_id: @team.id } }
      widget = Widget.find_by!(title: "Shop hours")
      assert_redirected_to widget_path(widget)
      assert_equal [ "left", 2, "team", @team ], [ widget.placement, widget.position, widget.viewer, widget.team ]

      get widget_path(widget)
      assert_response :success
      get widgets_path
      assert_response :success
      assert_match "Shop hours", response.body
    end
  end

  test "only architects can turn on ERB or set JavaScript" do
    with_feature do
      sign_in @admin
      post widgets_path, params: { widget: { title: "Sneaky", content: "<%= 1 + 1 %>", dynamic: "1", javascript: "alert(1)" } }
      widget = Widget.find_by!(title: "Sneaky")
      assert_not widget.dynamic
      assert_nil widget.javascript

      sign_in @architect
      patch widget_path(widget), params: { widget: { dynamic: "1", javascript: "console.log(root)" } }
      widget.reload
      assert widget.dynamic
      assert_equal "console.log(root)", widget.javascript
    end
  end

  test "admins who aren't architects can't change ERB content" do
    with_feature do
      widget = Widget.create!(title: "Live", content: "<%= 1 + 1 %>", dynamic: true)
      sign_in @admin
      patch widget_path(widget), params: { widget: { title: "Live count", content: "<%= User.delete_all %>" } }
      widget.reload
      assert_equal "Live count", widget.title
      assert_equal "<%= 1 + 1 %>", widget.content
    end
  end

  test "admins who aren't architects see ERB content and JavaScript read-only" do
    with_feature do
      widget = Widget.create!(title: "Live", content: "<%= 1 + 1 %>", dynamic: true, javascript: "console.log(root)")

      sign_in @admin
      get edit_widget_path(widget)
      assert_response :success
      assert_select "textarea[name='widget[content]']", 0
      assert_select "textarea[name='widget[javascript]']", 0
      assert_select "pre", text: "console.log(root)"

      sign_in @architect
      get edit_widget_path(widget)
      assert_select "textarea[name='widget[content]']", 1
      assert_select "textarea[name='widget[javascript]']", 1
    end
  end

  test "the body renders Markdown, with scoped CSS and the JavaScript for the browser" do
    with_feature do
      widget = Widget.create!(title: "Notice", content: "Hello **team**", stylesheet: "strong { color: red; }", javascript: "return () => {}")
      sign_in @member
      get body_widget_path(widget)
      assert_response :success
      assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(widget)} .widget-body strong", "team"
      assert_select "style", text: /\[data-widget="#{widget.neat_id}"\] \{\s*strong \{ color: red; \}/
      assert_select ".widget-body[data-widget-code-value=?]", "return () => {}"
    end
  end

  test "replace mode puts the content in a template for the shadow root" do
    with_feature do
      widget = Widget.create!(title: "Banner", content: "Kickoff", stylesheet: "p { color: red; }", style_mode: "replace")
      sign_in @member
      get body_widget_path(widget)
      assert_select ".widget-body[data-widget-mode-value=replace][data-widget-stylesheet-value=?]", "p { color: red; }"
      assert_select ".widget-body template", 1
      assert_select ".widget-body > style", 0
    end
  end

  test "ERB runs with the viewer and can hide the widget by rendering nothing" do
    with_feature do
      widget = Widget.create!(title: "Leaders", content: "<% if current_user.admin %>Secret<% end %>", dynamic: true)

      sign_in @admin
      get body_widget_path(widget)
      assert_select ".widget-body", text: /Secret/

      sign_in @member
      get body_widget_path(widget)
      assert_response :success
      assert_select ".widget-body", 0
    end
  end

  test "an ERB error shows a notice, with the message only for admins" do
    with_feature do
      widget = Widget.create!(title: "Broken", content: "<%= nope_not_a_method %>", dynamic: true)

      sign_in @member
      get body_widget_path(widget)
      assert_response :success
      assert_match "This widget couldn&#39;t be shown.", response.body
      assert_no_match "nope_not_a_method", response.body

      sign_in @admin
      get body_widget_path(widget)
      assert_match "nope_not_a_method", response.body
    end
  end

  test "people can't load the body of a widget they can't see" do
    with_feature do
      widget = Widget.create!(title: "Admins only", content: "Secret", viewer: "admin")
      sign_in @member
      get body_widget_path(widget)
      assert_redirected_to root_path
      assert_no_match "Secret", response.body
    end
  end

  test "the dashboard shows each person the widgets they can see, where they belong" do
    with_feature do
      top = Widget.create!(title: "Kickoff", placement: "top")
      left = Widget.create!(title: "Den A notes", placement: "left", viewer: "team", team: @team)
      hidden = Widget.create!(title: "Admins only", viewer: "admin")
      off = Widget.create!(title: "Switched off", enabled: false)

      sign_in @member
      get root_path
      assert_response :success
      assert_select "##{ActionView::RecordIdentifier.dom_id(top, :card)} turbo-frame[src=?]", body_widget_path(top)
      assert_select "##{ActionView::RecordIdentifier.dom_id(left, :card)}"
      assert_select "##{ActionView::RecordIdentifier.dom_id(hidden, :card)}", 0
      assert_select "##{ActionView::RecordIdentifier.dom_id(off, :card)}", 0
      assert body_index(top) < body_index(left), "top widgets come before the columns"
    end
  end

  test "the dashboard has no widgets while the feature is off" do
    with_settings(feature_widgets: "false") do
      Widget.create!(title: "Kickoff", placement: "top")
      sign_in @member
      get root_path
      assert_response :success
      assert_select ".widget", 0
    end
  end

  private

  def with_feature(&block)
    with_settings(feature_widgets: "true", &block)
  end

  def create_user(email, admin: false, architect: false)
    user = User.create!(email: email, password: "Password1!", admin: admin, architect: architect)
    Person.create!(user: user, first_name: email.split("@").first, last_name: "Test")
    user
  end

  def body_index(widget)
    response.body.index(ActionView::RecordIdentifier.dom_id(widget, :card))
  end
end
