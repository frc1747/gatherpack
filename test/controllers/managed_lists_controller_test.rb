require "test_helper"
require_relative "../support/managed_list_test_support"

class ManagedListsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ManagedListTestSupport

  setup do
    host! "localhost"
    create_managed_list_tables
    register_test_list

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")
    @member_user = User.create!(email: "member@example.com", password: "Password1!")
    Person.create!(user: @member_user, first_name: "Jo", last_name: "Member")

    @each = ManagedListTestUnit.create!(name: "Each")
    @box = ManagedListTestUnit.create!(name: "Box")
    @crate = ManagedListTestUnit.create!(name: "Crate", active: false)
  end

  teardown do
    unregister_test_list
  end

  # --- admin ----------------------------------------------------------------

  test "the list shows its description and active rows, with retired ones apart" do
    sign_in @admin_user

    get managed_list_path(:test_units)

    assert_response :success
    assert_select "h1", "Test Units"
    assert_match "The units test things are counted in.", response.body
    assert_select "#managed_list_active li", count: 2
    assert_select "#managed_list_retired", count: 0

    get managed_list_path(:test_units, status: "retired")
    assert_select "#managed_list_retired li", count: 1
    assert_select "#managed_list_retired", text: /Crate/
  end

  test "an admin can add a row with its extra fields" do
    sign_in @admin_user

    get new_managed_list_row_path(:test_units)
    assert_response :success
    assert_select "label", text: "Whole numbers only"

    assert_difference -> { ManagedListTestUnit.count }, 1 do
      post managed_list_rows_path(:test_units), params: { row: { name: "Pack", plural: "Packs", whole_numbers: "1", key: "pack" } }
    end

    pack = ManagedListTestUnit.find_by!(name: "Pack")
    assert_redirected_to managed_list_path(:test_units)
    assert pack.whole_numbers
    assert_nil pack.key, "key isn't editable on screen"
    assert_equal 3, pack.position
  end

  test "a duplicate name shows the form again" do
    sign_in @admin_user

    assert_no_difference -> { ManagedListTestUnit.count } do
      post managed_list_rows_path(:test_units), params: { row: { name: "box" } }
    end

    assert_response :unprocessable_entity
  end

  test "an admin can rename a row" do
    sign_in @admin_user

    get edit_managed_list_row_path(:test_units, @box)
    assert_response :success

    patch managed_list_row_path(:test_units, @box), params: { row: { name: "Carton" } }

    assert_redirected_to managed_list_path(:test_units)
    assert_equal "Carton", @box.reload.name
  end

  test "an admin can reorder rows" do
    sign_in @admin_user

    patch move_managed_list_row_path(:test_units, @box, direction: "up")

    assert_redirected_to managed_list_path(:test_units)
    assert_equal [ @box, @each ], ManagedListTestUnit.active.ordered.to_a
  end

  test "an admin can retire and restore a row" do
    sign_in @admin_user

    patch retire_managed_list_row_path(:test_units, @box)
    assert @box.reload.retired?

    patch restore_managed_list_row_path(:test_units, @box)
    assert @box.reload.active?
  end

  test "an admin can delete an unused row" do
    sign_in @admin_user

    assert_difference -> { ManagedListTestUnit.count }, -1 do
      delete managed_list_row_path(:test_units, @box)
    end
    assert_redirected_to managed_list_path(:test_units)
  end

  test "deleting a row in use is refused" do
    ManagedListTestThing.create!(name: "Bolts", unit_id: @box.id)
    sign_in @admin_user

    get managed_list_path(:test_units)
    assert_select "##{ActionView::RecordIdentifier.dom_id(@box)} a", text: "Merge into…"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@box)} button", text: "Delete", count: 0

    assert_no_difference -> { ManagedListTestUnit.count } do
      delete managed_list_row_path(:test_units, @box)
    end
    follow_redirect!
    assert_match "can&#39;t be deleted", response.body
  end

  test "an admin can merge a row in use into another" do
    bolts = ManagedListTestThing.create!(name: "Bolts", unit_id: @box.id)
    sign_in @admin_user

    get merge_managed_list_row_path(:test_units, @box)
    assert_response :success
    assert_select "select[name=target_id] option", text: "Each"
    assert_select "select[name=target_id] option", text: "Crate", count: 0

    post merge_managed_list_row_path(:test_units, @box), params: { target_id: @each.id }

    assert_redirected_to managed_list_path(:test_units)
    assert_equal @each.id, bolts.reload.unit_id
    assert_not ManagedListTestUnit.exists?(@box.id)
  end

  test "merging without a choice shows the form again" do
    sign_in @admin_user

    post merge_managed_list_row_path(:test_units, @box), params: { target_id: "" }

    assert_response :unprocessable_entity
    assert ManagedListTestUnit.exists?(@box.id)
  end

  # --- access ---------------------------------------------------------------

  test "a non-admin can't see or change the list" do
    sign_in @member_user

    get managed_list_path(:test_units)
    assert_redirected_to root_path

    assert_no_difference -> { ManagedListTestUnit.count } do
      post managed_list_rows_path(:test_units), params: { row: { name: "Pack" } }
    end
    patch retire_managed_list_row_path(:test_units, @box)
    assert @box.reload.active?
    delete managed_list_row_path(:test_units, @box)
    assert ManagedListTestUnit.exists?(@box.id)
  end

  test "a registration policy can let others manage the list" do
    member_user = @member_user
    register_test_list(policy: ->(user) { user == member_user })
    sign_in @member_user

    get managed_list_path(:test_units)
    assert_response :success

    post managed_list_rows_path(:test_units), params: { row: { name: "Pack" } }
    assert ManagedListTestUnit.exists?(name: "Pack")
  end

  test "an unknown list is not found" do
    sign_in @admin_user

    get managed_list_path(:no_such_list)

    assert_response :not_found
  end

  test "a list whose feature is off is not found" do
    register_test_list(feature: :turned_off_feature)
    sign_in @admin_user

    get managed_list_path(:test_units)

    assert_response :not_found
  end

  # --- setup page -----------------------------------------------------------

  test "the setup page shows the list under its section" do
    sign_in @admin_user

    get setup_path

    assert_response :success
    heading = css_select("h5").find { |h5| h5.text.strip == "Testing" }
    assert heading, "expected a Testing heading"
    button = heading.next_element.at_css("a[href='#{managed_list_path(:test_units)}']")
    assert_equal "Test Units", button&.text
  end

  test "the setup page leaves the list out while its feature is off" do
    register_test_list(feature: :turned_off_feature)
    sign_in @admin_user

    get setup_path

    assert_select "a[href=?]", managed_list_path(:test_units), count: 0
    assert_select "h5", text: "Testing", count: 0
  end

  test "the setup page hides the button from people who can't manage the list" do
    sign_in @member_user

    get setup_path

    assert_select "a[href=?]", managed_list_path(:test_units), count: 0
  end
end
