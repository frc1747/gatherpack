require "test_helper"
require_relative "../support/signups_world"

class SignupSheetsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    build_signups_world
    @sheet = create_world_sheet(description: "Help run the stand.", contact: "Pat, pat@example.com")
  end

  test "admin creates, edits and deletes a sheet" do
    sign_in person(:admin).user

    get new_signup_sheet_path
    assert_response :success

    assert_difference "SignupSheet.count" do
      post signup_sheets_path, params: { signup_sheet: sheet_params(team_id: @other_org.id, others_relationship_type_ids: [ "", @parent_of.id ]) }
    end
    sheet = SignupSheet.order(:created_at).last
    assert_redirected_to signup_sheet_path(sheet)
    assert_equal [ @parent_of.id ], sheet.others_relationship_type_ids
    assert_equal [ person(:admin) ], sheet.organizers.to_a

    get edit_signup_sheet_path(sheet)
    assert_response :success
    patch signup_sheet_path(sheet), params: { signup_sheet: { title: "Renamed", on_behalf_of_mode: "anyone" } }
    assert_redirected_to signup_sheet_path(sheet)
    assert_equal "Renamed", sheet.reload.title
    assert sheet.on_behalf_of_anyone?

    assert_difference "SignupSheet.count", -1 do
      delete signup_sheet_path(sheet)
    end
  end

  test "a sheet with sign-ups is archived instead of deleted" do
    sign_in person(:admin).user
    position = @sheet.signup_positions.create!(name: "Cashier")
    Signup.place!(slot: slot_for(position), person: person(:student), signed_up_by: person(:student))

    assert_no_difference "SignupSheet.count" do
      delete signup_sheet_path(@sheet)
    end
    assert @sheet.reload.archived?
  end

  test "a grant holder creates a sheet for a team in reach, and runs it" do
    with_organizer_grants("Sheet Organizer > Club") do
      sign_in person(:worker).user

      get new_signup_sheet_path
      assert_response :success
      assert_select "select#signup_sheet_team_id option", count: 2

      post signup_sheets_path, params: { signup_sheet: sheet_params(team_id: @club.id) }
      sheet = SignupSheet.order(:created_at).last
      assert_redirected_to signup_sheet_path(sheet)
      assert_equal person(:worker), sheet.created_by
      assert sheet.organizer?(person(:worker))

      patch signup_sheet_path(sheet), params: { signup_sheet: { team_id: @org.id } }
      assert_response :unprocessable_entity
      assert_equal @club, sheet.reload.team
    end
  end

  test "a grant holder can't create a sheet for a team out of reach" do
    with_organizer_grants("Sheet Organizer > Club") do
      sign_in person(:worker).user

      assert_no_difference "SignupSheet.count" do
        post signup_sheets_path, params: { signup_sheet: sheet_params(team_id: @org.id) }
      end
      assert_redirected_to root_path
    end
  end

  test "a member sees the sheet but can't create or change one" do
    sign_in person(:student).user

    get signup_sheets_path
    assert_response :success
    assert_select "a", text: "Snack Stand"
    assert_select "a", text: "New Sign-up Sheet", count: 0

    get signup_sheet_path(@sheet)
    assert_response :success
    assert_select "h1", text: "Snack Stand"
    assert_select "a", text: "Edit", count: 0

    get new_signup_sheet_path
    assert_redirected_to root_path
    assert_no_difference "SignupSheet.count" do
      post signup_sheets_path, params: { signup_sheet: sheet_params(team_id: @students.id) }
    end
    patch signup_sheet_path(@sheet), params: { signup_sheet: { title: "Mine now" } }
    assert_equal "Snack Stand", @sheet.reload.title
    delete signup_sheet_path(@sheet)
    assert SignupSheet.exists?(@sheet.id)
  end

  test "someone outside the audience can't see the sheet" do
    sign_in person(:outsider).user

    get signup_sheet_path(@sheet)
    assert_redirected_to root_path
  end

  private

  def sheet_params(**overrides)
    { title: "Bake Sale", description: "Bring something.", contact: "Sam", status: "draft", names_permission: "everyone",
      on_behalf_of_mode: "nobody_else", cancel_cutoff_hours: 0 }.merge(overrides)
  end
end
