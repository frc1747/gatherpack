require "test_helper"

class TeamSelectInputTest < ActionView::TestCase
  include SimpleForm::ActionViewExtensions::FormHelper

  setup do
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @art = Team.create!(name: "Art", team_type: team_types(:one))
  end

  test "the stored team is selected" do
    render_input(@robotics.id.to_s)

    assert_select "select" do
      assert_select "option[selected]", count: 1, text: "Robotics"
      assert_select "option[selected][value=?]", @robotics.id.to_s
    end
    assert_select "select[value]", count: 0
  end

  test "a blank value selects anyone signed in" do
    [ "", nil ].each do |value|
      render_input(value)

      assert_select "option[selected]", count: 1, text: "Anyone signed in"
    end
  end

  test "there is exactly one blank option, first, then teams by name" do
    render_input("")

    assert_select "option[value='']", count: 1
    labels = css_select("option").map(&:text)
    assert_equal "Anyone signed in", labels.first
    team_labels = labels.drop(1)
    assert_equal team_labels.sort, team_labels
    assert_includes team_labels, "Art"
    assert_includes team_labels, "Robotics"
  end

  private

  def render_input(value)
    @rendered = simple_form_for(:settings, url: "/settings/update") do |f|
      f.input :time_kiosk_users_team, as: :team_select, input_html: { value: value }
    end
  end

  def document_root_element
    Nokogiri::HTML::Document.parse(@rendered).root
  end
end

class TeamSelectInputSettingsPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "the settings page renders the kiosk team picker for an admin" do
    host! "localhost"
    Team.create!(name: "Kiosk", team_type: team_types(:one))
    user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: user, first_name: "Test", last_name: "Admin")
    sign_in user

    get settings_path

    assert_response :success
    assert_select "select[name=?]", "settings[time_kiosk_users_team]" do
      assert_select "option", text: "Anyone signed in"
      assert_select "option", text: "Kiosk"
    end
  end
end
