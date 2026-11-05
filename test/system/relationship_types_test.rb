require "application_system_test_case"

class RelationshipTypesTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    # The app builds URLs for localhost; browse there so redirects stay on-host.
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    @admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
    login_as @admin
  end

  teardown do
    Capybara.app_host = nil
    Warden.test_reset!
  end

  test "changing a type with relationships to a guardianship asks first" do
    type = relationship_types(:one)
    visit edit_relationship_type_path(type)
    select "Guardian while the child is a minor", from: "Guardianship"

    message = dismiss_confirm { click_on "Update Relationship type" }
    assert_equal "This makes the parent side of 1 relationship a guardian.", message
    assert type.reload.guardianship_none?

    message = accept_confirm { click_on "Update Relationship type" }
    assert_equal "This makes the parent side of 1 relationship a guardian.", message
    assert_text "Relationship type was successfully updated."
    assert type.reload.guardianship_minor?
    assert_text "Guardians can:"
  end

  test "changing a guardianship back to none asks first, moving between guardianships doesn't" do
    type = relationship_types(:one)
    type.update!(guardianship: :minor)

    visit edit_relationship_type_path(type)
    select "Guardian with the child's consent", from: "Guardianship"
    click_on "Update Relationship type"
    assert_text "Relationship type was successfully updated."
    assert type.reload.guardianship_consented?

    visit edit_relationship_type_path(type)
    select "None", from: "Guardianship"
    message = accept_confirm { click_on "Update Relationship type" }
    assert_equal "This stops the parent side of 1 relationship being a guardian.", message
    assert_text "Relationship type was successfully updated."
    assert type.reload.guardianship_none?
    assert_no_text "Guardians can:"
  end

  test "changing the selection back removes the question" do
    type = relationship_types(:one)
    visit edit_relationship_type_path(type)
    select "Guardian while the child is a minor", from: "Guardianship"
    select "None", from: "Guardianship"
    fill_in "Parent label", with: "Mentor of"

    click_on "Update Relationship type"

    assert_text "Relationship type was successfully updated."
    assert_equal "Mentor of", type.reload.parent_label
  end

  test "a new type doesn't ask" do
    visit new_relationship_type_path
    fill_in "Parent label", with: "Parent of"
    fill_in "Child label", with: "Child of"
    select "Guardian while the child is a minor", from: "Guardianship"

    click_on "Create Relationship type"

    assert_text "Relationship type was successfully created."
  end
end
