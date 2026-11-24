require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

class PersonFormsTabTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
  end

  test "the Forms tab shows the person's forms in a table under the profile tabs" do
    form = create_world_form("Trip Slip")
    with_settings(feature_forms: "true") do
      sign_in person(:a1).user
      get person_forms_path(person(:a1))

      assert_response :success
      assert_select ".navtab a.nav-link.active[href=?]", person_forms_path(person(:a1)), text: "Forms"
      assert_select ".card-header h1", text: "#{person(:a1).identifier_name}: Forms"
      assert_select "h2", text: "To do"
      assert_select ".table-responsive table.table tr##{dom_id(form)}" do
        assert_select "td a[href=?]", edit_form_response_path(form, person(:a1)), text: "Trip Slip"
        assert_select "td .badge", text: "Not started"
        assert_select "td a.btn.btn-sm.btn-primary", text: "Fill in"
      end
    end
  end

  test "a guardian sees their children's forms in their own table" do
    form = create_world_form("Trip Slip")
    with_settings(feature_forms: "true") do
      sign_in person(:parent_a1).user
      get person_forms_path(person(:parent_a1))

      assert_select "h2", text: "For your children"
      assert_select ".table-responsive tr##{dom_id(form)}_#{dom_id(person(:a1))}" do
        assert_select "td", text: person(:a1).identifier_name
        assert_select "a.btn.btn-sm.btn-primary[href=?]", edit_form_response_path(form, person(:a1)), text: "Fill in"
      end
    end
  end

  test "the Forms tab says so when there are no forms" do
    with_settings(feature_forms: "true") do
      sign_in person(:a1).user
      get person_forms_path(person(:a1))

      assert_select ".navtab a.nav-link.active", text: "Forms"
      assert_select "p.text-muted", text: "No forms to show."
      assert_select "table", count: 0
    end
  end
end
