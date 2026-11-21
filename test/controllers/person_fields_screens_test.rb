require "test_helper"
require_relative "../support/person_fields_world"
require_relative "../support/settings_test_helper"

# The person field and section screens follow the screen standard: one footer
# action and a More menu, an Archived pill, and small outline row buttons.
class PersonFieldsScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PersonFieldsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @allergies = create_world_field("Food Allergies", read: "family", write: "family")
  end

  test "the index footer has New Field and a More menu" do
    with_feature { as(:admin) { get person_fields_path } }

    assert_response :success
    assert_select ".card-footer" do
      assert_select "a.btn.btn-success", text: "New Field"
      assert_select ".dropdown-menu" do
        assert_select "a.dropdown-item", text: "Preview as…"
        assert_select "a.dropdown-item[href=?]", person_field_groups_path, text: "Sections"
      end
    end
    assert_select "a.btn-info", count: 0
    assert_select "a.btn-dark", count: 0
  end

  test "rows have small outline Edit and Archive buttons" do
    with_feature { as(:admin) { get person_fields_path } }

    assert_select "tr#person_field_#{@allergies.id}" do
      assert_select "a.btn-sm.btn-outline-secondary[href=?]", edit_person_field_path(@allergies), text: "Edit"
      assert_select "form[action=?] button.btn-sm.btn-outline-secondary[data-turbo-confirm]", archive_person_field_path(@allergies), text: "Archive"
    end
  end

  test "the Archived pill shows archived fields, which can be restored" do
    with_feature do
      as(:admin) do
        patch archive_person_field_path(@allergies)
        assert @allergies.reload.archived?

        get person_fields_path
        assert_select "tr#person_field_#{@allergies.id}", count: 0
        assert_select ".screen-filter-pills a[href=?]", person_fields_path(status: "archived"), text: "Archived (1)"

        get person_fields_path(status: "archived")
        assert_select ".screen-filter-pills a[aria-current=true]", text: "Archived (1)"
        assert_select "tr#person_field_#{@allergies.id}" do
          assert_select "form[action=?][data-turbo-confirm] button.btn-outline-secondary", restore_person_field_path(@allergies), text: "Restore"
        end

        patch restore_person_field_path(@allergies)
        assert_not @allergies.reload.archived?
        get person_fields_path(status: "archived")
        assert_select "tr#person_field_#{@allergies.id}", count: 0
      end
    end
  end

  test "field forms cancel with a secondary button and save" do
    with_feature do
      as(:admin) do
        get new_person_field_path
        assert_select "a.btn-secondary[href=?]", person_fields_path, text: "Cancel"

        get edit_person_field_path(@allergies)
        assert_select "a.btn-secondary[href=?]", person_fields_path, text: "Cancel"
        assert_select "a.btn-warning", count: 0

        patch person_field_path(@allergies), params: { person_field: { name: "Allergies" } }
        assert_redirected_to person_fields_path
        assert_equal "Allergies", @allergies.reload.name

        get person_field_path(@allergies)
        assert_select "a.btn-warning[href=?]", edit_person_field_path(@allergies), text: "Edit"
        assert_select "a", text: "Back", count: 0
      end
    end
  end

  test "section forms cancel with a secondary button and save" do
    with_feature do
      as(:admin) do
        get new_person_field_group_path
        assert_select "a.btn-secondary[href=?]", person_field_groups_path, text: "Cancel"

        post person_field_groups_path, params: { person_field_group: { name: "Medical", position: 0 } }
        medical = PersonFieldGroup.find_by!(name: "Medical")

        get edit_person_field_group_path(medical)
        assert_select "a.btn-secondary[href=?]", person_field_groups_path, text: "Cancel"
        patch person_field_group_path(medical), params: { person_field_group: { name: "Health" } }
        assert_equal "Health", medical.reload.name

        get person_field_groups_path
        assert_select ".table-responsive table"
        assert_select "a.btn-success", text: "New Section"
      end
    end
  end

  test "preview results sit in a responsive table" do
    with_feature { as(:admin) { get preview_person_fields_path(preview: { viewer_id: person(:admin).id, subject_id: person(:a1).id }) } }

    assert_select ".table-responsive table"
  end

  private

  def with_feature(&block)
    with_settings(feature_person_fields: "true", &block)
  end

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
