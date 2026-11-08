require "test_helper"

class CalendarNotesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    # Robotics (run by @manager, @member on it)
    # Drama (unrelated)
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @drama = Team.create!(name: "Drama", team_type: team_types(:one))

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")

    @manager_user = User.create!(email: "manager@example.com", password: "Password1!")
    @manager = Person.create!(user: @manager_user, first_name: "Mary", last_name: "Manager")
    Membership.create!(person: @manager, team: @robotics, manager: true)

    @member_user = User.create!(email: "member@example.com", password: "Password1!")
    @member = Person.create!(user: @member_user, first_name: "Sam", last_name: "Student")
    Membership.create!(person: @member, team: @robotics)

    @team_note = CalendarNote.create!(name: "Robotics build deadline", start_time: 2.days.from_now, noteable: @robotics)
    @global_note = CalendarNote.create!(name: "Building closed", start_time: 3.days.from_now, noteable: nil)
  end

  # --- create -------------------------------------------------------------

  test "a member cannot post a note onto a team" do
    sign_in @member_user

    [ @drama, @robotics ].each do |team|
      assert_no_difference -> { CalendarNote.where(noteable: team).count }, "a member attached a calendar note to #{team.name}" do
        post calendar_notes_path, params: { calendar_note: note_params(noteable_nid: team.neat_id) }
      end
      assert_redirected_to root_path
    end
  end

  test "a member cannot post an organisation-wide note" do
    sign_in @member_user

    assert_no_difference -> { CalendarNote.count } do
      post calendar_notes_path, params: { calendar_note: note_params(noteable_nid: "") }
    end
    assert_redirected_to root_path
  end

  test "a member can add a note on themselves" do
    sign_in @member_user

    post calendar_notes_path, params: { calendar_note: note_params(noteable_nid: @member.neat_id) }

    assert_redirected_to calendar_note_path(CalendarNote.find_by!(name: "Practice cancelled", noteable: @member))
  end

  test "a manager can add a note on their team" do
    sign_in @manager_user

    post calendar_notes_path, params: { calendar_note: note_params(noteable_nid: @robotics.neat_id) }

    assert_redirected_to calendar_note_path(CalendarNote.find_by!(name: "Practice cancelled", noteable: @robotics))
  end

  # --- update -------------------------------------------------------------

  test "a member cannot rewrite a team calendar note" do
    sign_in @member_user

    patch calendar_note_path(@team_note), params: { calendar_note: { name: "Deadline cancelled" } }

    assert_equal "Robotics build deadline", @team_note.reload.name, "a member without a manager role renamed the team's calendar note"
    assert_redirected_to root_path
  end

  test "a member cannot move their own note onto a team" do
    own_note = CalendarNote.create!(name: "Dentist", start_time: 1.day.from_now, noteable: @member)
    sign_in @member_user

    patch calendar_note_path(own_note), params: { calendar_note: { noteable_nid: @robotics.neat_id } }

    assert_equal @member, own_note.reload.noteable, "a member moved their note onto a team"
    assert_redirected_to root_path
  end

  test "a manager cannot move their team's note onto a team they don't manage" do
    sign_in @manager_user

    patch calendar_note_path(@team_note), params: { calendar_note: { noteable_nid: @drama.neat_id } }

    assert_equal @robotics, @team_note.reload.noteable
    assert_redirected_to root_path
  end

  test "a manager can edit their team's note" do
    sign_in @manager_user

    patch calendar_note_path(@team_note), params: { calendar_note: { name: "Deadline moved" } }

    assert_redirected_to calendar_note_path(@team_note)
    assert_equal "Deadline moved", @team_note.reload.name
  end

  # --- destroy ------------------------------------------------------------

  test "a member cannot delete an organisation-wide calendar note" do
    sign_in @member_user

    delete calendar_note_path(@global_note)

    assert CalendarNote.exists?(@global_note.id), "a member deleted an organisation-wide calendar note"
    assert_redirected_to root_path
  end

  test "an admin can delete an organisation-wide calendar note" do
    sign_in @admin_user

    delete calendar_note_path(@global_note)

    assert_not CalendarNote.exists?(@global_note.id)
    assert_redirected_to calendar_index_path
  end

  # --- views --------------------------------------------------------------

  test "the note page only offers edit and delete to those who may use them" do
    sign_in @member_user
    get calendar_note_path(@team_note)

    assert_response :success
    assert_select "a[href='#{edit_calendar_note_path(@team_note)}']", count: 0
    assert_select "a[href='#{calendar_note_path(@team_note)}'][data-turbo-method='delete']", count: 0

    sign_in @manager_user
    get calendar_note_path(@team_note)

    assert_select "a[href='#{edit_calendar_note_path(@team_note)}']"
    assert_select "a[href='#{calendar_note_path(@team_note)}'][data-turbo-method='delete']"
  end

  test "a member can open the new note form" do
    sign_in @member_user

    get new_calendar_note_path

    assert_response :success
  end

  private

  def note_params(**attributes)
    { name: "Practice cancelled", start_time: 1.day.from_now }.merge(attributes)
  end
end
