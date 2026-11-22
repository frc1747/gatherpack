require "test_helper"
require_relative "../support/managed_list_test_support"

# The managed list screen follows the screen standard: small outline row
# buttons, Merge and Delete in a per-row More, and retired rows behind a
# Retired filter pill where they can be restored.
class ManagedListsScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ManagedListTestSupport

  setup do
    host! "localhost"
    create_managed_list_tables
    register_test_list

    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    sign_in admin

    @each = ManagedListTestUnit.create!(name: "Each")
    @box = ManagedListTestUnit.create!(name: "Box")
    @crate = ManagedListTestUnit.create!(name: "Crate", active: false)
  end

  teardown do
    unregister_test_list
  end

  test "rows have small Edit, arrows and Retire, with Merge in a per-row More" do
    ManagedListTestThing.create!(name: "Bolts", unit_id: @box.id)

    get managed_list_path(:test_units)

    assert_select "##{dom_id(@box)}" do
      assert_select "a.btn-sm.btn-outline-secondary[href=?]", edit_managed_list_row_path(:test_units, @box), text: "Edit"
      assert_select "form[action=?] button.btn-sm.btn-outline-secondary", move_managed_list_row_path(:test_units, @box, direction: "up")
      assert_select "form[action=?][data-turbo-confirm] button.btn-sm.btn-outline-secondary", retire_managed_list_row_path(:test_units, @box), text: "Retire"
      assert_select ".dropdown-menu a.dropdown-item[href=?]", merge_managed_list_row_path(:test_units, @box), text: "Merge into…"
    end
    assert_select "##{dom_id(@each)} .dropdown-menu button.dropdown-item.text-danger", text: "Delete"
    assert_select ".btn-outline-warning", count: 0
    assert_select ".card-footer a.btn-success[href=?]", new_managed_list_row_path(:test_units), text: "New Test Unit"
  end

  test "rows reorder, retire, restore and merge as before" do
    patch move_managed_list_row_path(:test_units, @box, direction: "up")
    assert_equal [ @box, @each ], ManagedListTestUnit.active.ordered.to_a

    patch retire_managed_list_row_path(:test_units, @box)
    assert @box.reload.retired?

    get managed_list_path(:test_units)
    assert_select "##{dom_id(@box)}", count: 0
    assert_select ".screen-filter-pills a[href=?]", managed_list_path(:test_units, status: "retired"), text: "Retired (2)"

    get managed_list_path(:test_units, status: "retired")
    assert_select ".screen-filter-pills a[aria-current=true]", text: "Retired (2)"
    assert_select "##{dom_id(@box)} form[action=?][data-turbo-confirm] button.btn-outline-secondary", restore_managed_list_row_path(:test_units, @box), text: "Restore"

    patch restore_managed_list_row_path(:test_units, @box)
    assert @box.reload.active?

    bolts = ManagedListTestThing.create!(name: "Bolts", unit_id: @box.id)
    post merge_managed_list_row_path(:test_units, @box), params: { target_id: @each.id }
    assert_equal @each.id, bolts.reload.unit_id
  end

  test "row forms cancel with a secondary button and save" do
    get new_managed_list_row_path(:test_units)
    assert_select "a.btn-secondary[href=?]", managed_list_path(:test_units), text: "Cancel"
    assert_select "a.btn-warning", count: 0

    get edit_managed_list_row_path(:test_units, @box)
    assert_select "a.btn-secondary[href=?]", managed_list_path(:test_units), text: "Cancel"
    patch managed_list_row_path(:test_units, @box), params: { row: { name: "Carton" } }
    assert_redirected_to managed_list_path(:test_units)
    assert_equal "Carton", @box.reload.name

    ManagedListTestThing.create!(name: "Bolts", unit_id: @box.id)
    get merge_managed_list_row_path(:test_units, @box)
    assert_select "a.btn-secondary[href=?]", managed_list_path(:test_units), text: "Cancel"
    assert_select "input.btn-danger[value=Merge]"
  end

  private

  def dom_id(record)
    ActionView::RecordIdentifier.dom_id(record)
  end
end
