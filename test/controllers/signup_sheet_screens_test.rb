require "test_helper"
require_relative "../support/signups_world"

# The sheet page's state line and actions, Taking sign-ups on the setup
# page's Details tab, and Archive and Restore. worker organizes the sheet;
# student can sign up on it.
class SignupSheetScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-01 12:00")
    build_signups_world
    @restore_settings = apply_settings(signups_organizers: "Sheet Organizer > Club")
    @sheet = create_world_sheet(created_by: person(:worker))
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 3)
  end

  teardown do
    @restore_settings&.call
  end

  test "each Taking sign-ups choice sets the status, and the sheet page says it in words" do
    sign_in person(:worker).user

    get edit_signup_sheet_path(@sheet, tab: "details")
    assert_select "input[type=radio][name='signup_sheet[status]']", 3
    assert_select "input[type=radio][name='signup_sheet[status]'][value=archived]", count: 0

    { "draft" => "Not taking sign-ups yet", "open" => "Taking sign-ups until Oct 24", "closed" => "Closed" }.each do |status, words|
      patch signup_sheet_path(@sheet), params: { tab: "details", signup_sheet: { status: status } }
      assert_redirected_to signup_sheet_path(@sheet)
      assert_equal status, @sheet.reload.status

      get signup_sheet_path(@sheet)
      assert_select ".card-header .screen-state-line", text: /#{words}/
    end
  end

  test "Taking sign-ups can't archive a sheet" do
    sign_in person(:worker).user

    patch signup_sheet_path(@sheet), params: { tab: "details", signup_sheet: { status: "archived", title: "Renamed" } }
    assert_equal [ "open", "Renamed" ], @sheet.reload.values_at(:status, :title)
  end

  test "a new sheet's Taking sign-ups starts at Not yet" do
    sign_in person(:worker).user

    get new_signup_sheet_path
    assert_select "input[type=radio][name='signup_sheet[status]'][value=draft][checked]"
    assert_select "a.btn-secondary", text: "Cancel"
  end

  test "an archived sheet says Archived, and its Edit page offers no choice and can't change the status" do
    @sheet.archived!
    sign_in person(:worker).user

    get signup_sheet_path(@sheet)
    assert_select ".card-header .screen-state-line", text: "Archived"

    get edit_signup_sheet_path(@sheet, tab: "details")
    assert_select ".card-header .screen-state-line", text: "Archived"
    assert_select "input[name='signup_sheet[status]']", count: 0

    patch signup_sheet_path(@sheet), params: { tab: "details", signup_sheet: { status: "open" } }
    assert @sheet.reload.archived?
  end

  test "an organizer archives a sheet with sign-ups and one without; both are kept" do
    other = create_world_sheet("Bake Sale", created_by: person(:worker))
    Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:student))
    sign_in person(:worker).user

    [ @sheet, other ].each do |sheet|
      assert_no_difference "SignupSheet.count" do
        post archive_signup_sheet_path(sheet)
      end
      assert_redirected_to signup_sheet_path(sheet)
      assert_equal "Sheet archived.", flash[:notice]
      assert sheet.reload.archived?
    end
  end

  test "only an organizer can archive, and not twice" do
    sign_in person(:student).user
    post archive_signup_sheet_path(@sheet)
    assert_redirected_to root_path
    assert @sheet.reload.open?

    @sheet.archived!
    sign_in person(:worker).user
    post archive_signup_sheet_path(@sheet)
    assert_redirected_to root_path
    assert @sheet.reload.archived?
  end

  test "an organizer restores an archived sheet, closed" do
    @sheet.archived!
    sign_in person(:worker).user

    post restore_signup_sheet_path(@sheet)
    assert_redirected_to signup_sheet_path(@sheet)
    assert_equal "Sheet restored. It isn't taking sign-ups.", flash[:notice]
    assert @sheet.reload.closed?
  end

  test "only an organizer can restore, and only an archived sheet" do
    @sheet.archived!
    sign_in person(:student).user
    post restore_signup_sheet_path(@sheet)
    assert_redirected_to root_path
    assert @sheet.reload.archived?

    @sheet.open!
    sign_in person(:worker).user
    post restore_signup_sheet_path(@sheet)
    assert_redirected_to root_path
    assert @sheet.reload.open?
  end

  test "an organizer's footer: Edit, Roster, and More with Archive then Delete" do
    sign_in person(:worker).user

    get signup_sheet_path(@sheet)
    assert_select ".card-footer.screen-action-row" do
      assert_select "> a.btn-warning[href=?]", edit_signup_sheet_path(@sheet, tab: "details"), text: "Edit"
      assert_select "> a.btn-secondary[href=?]", roster_signup_sheet_path(@sheet), text: "Roster"
      assert_select ".dropdown > button", text: "More"
      assert_select ".dropdown-menu > li:not(.d-md-none)", 2
      assert_select ".dropdown-menu > li:not(.d-md-none) form[action=?][method=post][data-turbo-confirm=?]", archive_signup_sheet_path(@sheet),
        "Archive this sheet? It's hidden from lists; sign-ups are kept." do
        assert_select "input[name=_method]", count: 0
      end
      assert_select ".dropdown-menu > li:last-child form[action=?][data-turbo-confirm=?]", signup_sheet_path(@sheet), "Delete this sheet?" do
        assert_select "input[name=_method][value=delete]"
        assert_select "button.text-danger", text: "Delete"
      end
      assert_select "button", text: "Restore", count: 0
    end
  end

  test "a sheet with sign-ups offers Archive in More but not Delete, and Archive never sends DELETE" do
    Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:student))
    sign_in person(:worker).user

    get signup_sheet_path(@sheet)
    assert_select ".screen-action-row" do
      assert_select ".dropdown > button", text: "More"
      assert_select ".dropdown-menu > li:not(.d-md-none) form[action=?][data-turbo-confirm=?]", archive_signup_sheet_path(@sheet),
        "Archive this sheet? It's hidden from lists; sign-ups are kept."
      assert_select "button", text: "Delete", count: 0
      assert_select "input[name=_method][value=delete]", count: 0
    end
  end

  test "an archived sheet offers Restore instead of Archive" do
    Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:student))
    @sheet.archived!
    sign_in person(:worker).user

    get signup_sheet_path(@sheet)
    assert_select ".screen-action-row" do
      assert_select ".dropdown-menu > li:not(.d-md-none) form[action=?][data-turbo-confirm=?]", restore_signup_sheet_path(@sheet),
        "Restore this sheet? It comes back closed."
      assert_select "button", text: "Archive", count: 0
      assert_select "button", text: "Delete", count: 0
    end
  end

  test "a member sees none of the sheet's actions" do
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_response :success
    assert_select ".screen-action-row", count: 0
    assert_select "a", text: "Edit", count: 0
    assert_select "a", text: "Roster", count: 0
    assert_select "button", text: "More", count: 0
  end

  test "a member's Cancel sign-up names the date, and the cutoff still applies" do
    @sheet.update!(cancel_cutoff_hours: 24)
    signup = Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:student))
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_select "#my_signups button.btn-outline-danger[data-turbo-confirm=?]", "Cancel your sign-up for Sat Oct 24?", text: "Cancel sign-up"
    assert_select "#my_signups a.btn-outline-secondary", text: "Change"

    # A jump of weeks can outlast an idle sign-in session, so sign in again after each one.
    travel_to @event.start_time - 1.hour
    sign_in person(:student).user
    get signup_sheet_path(@sheet)
    assert_select "#my_signups button", text: "Cancel sign-up", count: 0
    delete signup_sheet_signup_path(@sheet, signup)
    assert signup.reload.active?

    travel_to Time.zone.parse("2026-10-01 12:00")
    sign_in person(:student).user
    delete signup_sheet_signup_path(@sheet, signup)
    assert signup.reload.cancelled?
  end

  test "the Details tab saves only the details; the other tabs keep their own flows" do
    sign_in person(:worker).user

    patch signup_sheet_path(@sheet), params: { tab: "details", signup_sheet: { title: "Snack Bar" } }
    assert_equal "Snack Bar", @sheet.reload.title

    patch signup_sheet_path(@sheet), params: { tab: "details", signup_sheet: { title: "" } }
    assert_response :unprocessable_entity
    assert_select "input[name=tab][value=details]"

    post signup_sheet_signup_positions_path(@sheet), params: { signup_position: { name: "Runner", kind: "people" } }
    position = @sheet.signup_positions.find_by!(name: "Runner")
    delete signup_sheet_signup_position_path(@sheet, position)
    assert_redirected_to edit_signup_sheet_path(@sheet, tab: "positions")

    sheet_event = @sheet.signup_sheet_events.first
    delete signup_sheet_signup_sheet_event_path(@sheet, sheet_event)
    assert_redirected_to edit_signup_sheet_path(@sheet, tab: "dates")
  end

  test "the list shows each sheet's state in the same words" do
    create_world_sheet("Bake Sale", status: :closed, created_by: person(:worker))
    sign_in person(:worker).user

    get signup_sheets_path
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(@sheet)} td", text: "Taking sign-ups until Oct 24"
    assert_select "tr td", text: "Closed"
    assert_select ".table-responsive table"

    get signup_sheets_path(q: { title_cont: "Bake" })
    assert_select "tbody tr", 1
  end

  test "on a sheet with several dates and none chosen, More has Mark all brought for each date" do
    @sheet.signup_positions.create!(name: "Dessert", kind: :items, unit: "pies", capacity: 10)
    later = create_world_event("Second Game", Time.zone.parse("2026-10-31 10:00"))
    @sheet.signup_sheet_events.create!(event: later)
    sign_in person(:worker).user

    get roster_signup_sheet_path(@sheet)
    assert_select ".screen-action-row .dropdown-menu > li:not(.d-md-none)" do
      assert_select "form[action=?][data-turbo-confirm=?] button", mark_all_brought_signup_sheet_roster_signups_path(@sheet, event_id: @event.id),
        "Mark every item sign-up on Sat Oct 24 brought? Your own and your family's are left for another organizer to mark.",
        text: "Mark all brought: Oct 24"
      assert_select "form[action=?] button", mark_all_brought_signup_sheet_roster_signups_path(@sheet, event_id: later.id), text: "Mark all brought: Oct 31"
    end

    get roster_signup_sheet_path(@sheet, event_id: later.id)
    assert_select ".screen-action-row .dropdown-menu button", text: /Mark all brought/, count: 1
    assert_select ".screen-action-row form[action=?] button", mark_all_brought_signup_sheet_roster_signups_path(@sheet, event_id: later.id),
      text: "Mark all brought"
  end

  test "people who run sheets can list their archived sheets, to open and restore them" do
    archived = create_world_sheet("Last Season", status: :archived, created_by: person(:worker))
    sign_in person(:worker).user

    get signup_sheets_path
    assert_select "select[name=archived]"
    assert_select "a", text: "Last Season", count: 0

    get signup_sheets_path(archived: "1")
    assert_select "tbody tr", 1
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(archived)}" do
      assert_select "a[href=?]", signup_sheet_path(archived), text: "Last Season"
      assert_select "td", text: "Archived"
    end

    get signup_sheet_path(archived)
    assert_select "form[action=?]", restore_signup_sheet_path(archived)
  end

  test "a member gets no Archived choice and never sees archived sheets in the list" do
    create_world_sheet("Last Season", status: :archived, created_by: person(:worker))
    sign_in person(:student).user

    get signup_sheets_path(archived: "1")
    assert_select "select[name=archived]", count: 0
    assert_select "a", text: "Last Season", count: 0
    assert_select "a", text: "Snack Stand"
  end

  test "the Team filter offers only teams of sheets in the list" do
    create_world_sheet("Closed Sale", team: @students, status: :closed)
    sign_in person(:student).user

    get signup_sheets_path
    assert_select "select[name='q[team_id_eq]'] option", text: "Club"
    assert_select "select[name='q[team_id_eq]'] option", text: "Students", count: 0
  end

  test "the roster filters by status with counts, prints, and has no Set up" do
    Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:student))
    sign_in person(:worker).user

    get roster_signup_sheet_path(@sheet)
    assert_select ".screen-filter-bar a", text: "Signed up (1)"
    assert_select ".screen-filter-bar .screen-table-actions button[type=button][data-action='print#print']", text: "Print"
    assert_select ".screen-filter-bar select[name=event_id]"
    assert_select ".screen-filter-bar select[name=signup_position_id]"
    assert_select ".screen-action-row a.btn-success", text: "Add a sign-up"
    assert_select ".screen-action-row a", text: "Message"
    assert_select "a", text: "Set up", count: 0

    get roster_signup_sheet_path(@sheet, status: "cancelled")
    assert_select "#roster", count: 0
  end
end
