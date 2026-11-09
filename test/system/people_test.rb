require "application_system_test_case"

class PeopleTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    @server_host, Capybara.server_host = Capybara.server_host, "localhost"
    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    sign_in admin
  end

  teardown do
    Capybara.server_host = @server_host
  end

  test "search form is hidden until the Search button is pressed on a phone" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit people_path

    assert_no_field "Phone"
    button = find("button", text: "Search", match: :first)
    assert_operator button.native.rect.height, :>=, 44

    button.click
    assert_field "Phone"
  end
end
