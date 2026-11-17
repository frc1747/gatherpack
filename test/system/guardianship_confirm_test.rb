require "application_system_test_case"

class GuardianshipConfirmTest < ApplicationSystemTestCase
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

  test "widening a type with relationships doesn't ask and is refused" do
    type = relationship_types(:one)
    visit edit_relationship_type_path(type)
    select "Guardian while the child is a minor", from: "Guardianship"

    click_on "Update Relationship type"

    assert_text "can't grant more while this type already has links"
    assert type.reload.guardianship_none?
  end

  test "changing a guardianship back to none asks first, moving between guardianships doesn't" do
    type = relationship_types(:one)
    type.update_column(:guardianship, RelationshipType.guardianships[:consented])

    visit edit_relationship_type_path(type)
    select "Guardian while the child is a minor", from: "Guardianship"
    click_on "Update Relationship type"
    assert_text "Relationship type was successfully updated."
    assert type.reload.guardianship_minor?

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

  test "turning on contact details for a type with relationships asks first, turning it off doesn't" do
    type = relationship_types(:one)
    question = "This shows the phone and email of the parent side of 1 relationship to anyone who can see the child. Check them first if members could ever add this type."
    visit edit_relationship_type_path(type)
    check "Show contact details"

    assert_equal question, dismiss_confirm { click_on "Update Relationship type" }
    assert_not type.reload.show_contact_details?

    assert_equal question, accept_confirm { click_on "Update Relationship type" }
    assert_text "Relationship type was successfully updated."
    assert type.reload.show_contact_details?

    visit edit_relationship_type_path(type)
    uncheck "Show contact details"
    click_on "Update Relationship type"
    assert_text "Relationship type was successfully updated."
    assert_not type.reload.show_contact_details?
  end

  test "ticking contact details while picking a wider guardianship asks only about contact details" do
    type = relationship_types(:one)
    visit edit_relationship_type_path(type)
    select "Guardian while the child is a minor", from: "Guardianship"
    check "Show contact details"

    message = dismiss_confirm { click_on "Update Relationship type" }

    assert_not_includes message, "This makes the parent side"
    assert_includes message, "This shows the phone and email"
  end

  test "unticking contact details again removes the question" do
    type = relationship_types(:one)
    visit edit_relationship_type_path(type)
    check "Show contact details"
    uncheck "Show contact details"
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
