require "test_helper"

# Every controller of the app verifies that its actions authorize (or, for
# index, scope) through Pundit, so a forgotten check fails loudly. These are
# the controllers that used to inherit ApplicationController directly; each
# keeps the answers it gave admins and members before.
class AuthorizationVerificationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Controllers that inherit ApplicationController but have no record to
  # authorize, with the reason.
  UNVERIFIED = {
    "DeviseController" => "signing in, up and out happens before there is a user to authorize"
  }.freeze

  class ForgetfulController < InternalController
    def show
      head :ok
    end
  end

  setup do
    host! "localhost"
    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @admin = create_person("admin@example.com", admin: true)
    @member = create_person("member@example.com", team: @team)
    @teammate = create_person("teammate@example.com", team: @team)
  end

  test "every controller verifies authorization" do
    Rails.application.eager_load!

    unverified = ApplicationController.descendants.reject do |controller|
      controller._process_action_callbacks.any? { |callback| callback.kind == :after && callback.filter == :verify_pundit_authorization } ||
        UNVERIFIED.keys.any? { |name| controller <= name.constantize }
    end

    assert_empty unverified.map(&:name).sort
  end

  test "an action that forgets to authorize raises" do
    sign_in @member.user

    with_routing do |routes|
      routes.draw { get "/forgetful", to: "authorization_verification_test/forgetful#show" }

      assert_raises(Pundit::AuthorizationNotPerformedError) { get "/forgetful" }
    end
  end

  # --- pages ----------------------------------------------------------------

  test "pages answer admins and members as before" do
    page = Page.create!(title: "Handbook", content: "Hello", viewer: "user", editor: "admin")

    sign_in @admin.user
    [ pages_path, page_path(page), new_page_path, edit_page_path(page) ].each do |path|
      get path
      assert_response :success, path
    end

    sign_in @member.user
    [ pages_path, page_path(page), new_page_path ].each do |path|
      get path
      assert_response :success, path
    end
    get edit_page_path(page)
    assert_redirected_to root_path
  end

  test "a member can't change or delete a page only admins edit" do
    page = Page.create!(title: "Handbook", content: "Hello", viewer: "user", editor: "admin")
    sign_in @member.user

    patch page_path(page), params: { page: { title: "Changed" } }
    assert_redirected_to root_path
    assert_equal "Handbook", page.reload.title

    assert_no_difference -> { Page.count } do
      delete page_path(page)
    end
  end

  test "an admin creates, changes and deletes a page" do
    sign_in @admin.user

    assert_difference -> { Page.count }, 1 do
      post pages_path, params: { page: { title: "Rules", content: "Be kind", viewer: "user", editor: "admin" } }
    end
    page = Page.find_by!(title: "Rules")
    assert_redirected_to page_path(page)

    patch page_path(page), params: { page: { title: "House rules" } }
    assert_redirected_to page_path(page)
    assert_equal "House rules", page.reload.title

    assert_difference -> { Page.count }, -1 do
      delete page_path(page)
    end
    assert_redirected_to pages_path
  end

  test "a member creates, changes and deletes a page any user edits" do
    sign_in @member.user

    assert_difference -> { Page.count }, 1 do
      post pages_path, params: { page: { title: "Notes", content: "Hello", viewer: "user", editor: "user" } }
    end
    page = Page.find_by!(title: "Notes")
    assert_redirected_to page_path(page)

    patch page_path(page), params: { page: { title: "Shared notes" } }
    assert_redirected_to page_path(page)
    assert_equal "Shared notes", page.reload.title

    assert_difference -> { Page.count }, -1 do
      delete page_path(page)
    end
    assert_redirected_to pages_path
  end

  # --- relationships --------------------------------------------------------

  test "admins and members open the new relationship form" do
    [ @admin, @member ].each do |person|
      sign_in person.user

      get new_person_relationship_path(@member)
      assert_response :success, person.user.email
    end
  end

  test "admins and members relate two people they can see" do
    [ @admin, @member ].each do |person|
      sign_in person.user

      assert_difference -> { Relationship.count }, 1, person.user.email do
        post person_relationships_path(@member), params: { relationship: { start_node: "#{relationship_type.id}:p", child_id: @teammate.id } }
      end
      assert_redirected_to person_path(@member)
    end
  end

  test "a relationship missing its other side still asks for it" do
    sign_in @member.user

    post person_relationships_path(@member), params: { relationship: { relationship_type_id: relationship_type.id, start_node: "#{relationship_type.id}:p" } }

    assert_response :precondition_required
  end

  test "the people in a relationship reverse and delete it, others don't" do
    relationship = Relationship.new(relationship_type: relationship_type, parent: @member, child: @teammate, created_by: @member)
    relationship.save!(validate: false)
    bystander = create_person("bystander@example.com", team: @team)

    sign_in bystander.user
    post reverse_person_relationship_path(@member, relationship)
    assert_redirected_to root_path
    assert_equal @member, relationship.reload.parent
    assert_no_difference -> { Relationship.count } do
      delete person_relationship_path(@member, relationship)
    end

    sign_in @member.user
    post reverse_person_relationship_path(@member, relationship)
    assert_redirected_to relationships_person_path(@member)
    assert_equal @teammate, relationship.reload.parent
    assert_difference -> { Relationship.count }, -1 do
      delete person_relationship_path(@member, relationship)
    end
  end

  # --- calendar, search, dashboard, kiosk -----------------------------------

  test "the calendar, search and dashboard open for admins and members" do
    [ @admin, @member ].each do |person|
      sign_in person.user

      [ calendar_index_path, search_path(q: "a"), search_path(q: "a", scope: "me"),
        search_path(q: "a", scope: "managed_people managed_teams"), root_path, setup_path ].each do |path|
        get path
        assert_response :success, "#{path} for #{person.user.email}"
      end

      get combo_search_path(q: "a", scope: "people me"), as: :turbo_stream
      assert_response :success

      get calendar_calendar_index_path(format: :json), params: { start_time: 1.month.ago.to_date.to_s, end_time: 1.month.from_now.to_date.to_s, events: 1, notes: 1 }
      assert_response :success
    end
  end

  test "the kiosk opens for admins but not members" do
    sign_in @admin.user
    get time_kiosk_path
    assert_response :success

    sign_in @member.user
    get time_kiosk_path
    assert_response :forbidden
  end

  test "the calendar feed sends a browser back to the calendar" do
    [ @admin, @member ].each do |person|
      sign_in person.user

      get calendar_calendar_index_path
      assert_redirected_to calendar_index_path
    end
  end

  test "admins and kiosk accounts punch in and out at the kiosk" do
    period = TimeClockPeriod.create!(name: "Build", team: @team, start_time: 1.day.ago, end_time: 1.day.from_now, permission: :added_by_team_member)
    kiosk = create_person("kiosk@example.com")
    kiosk.user.update!(kiosk: true)
    time_kiosk = TimeKiosk.new
    time_kiosk.person = @teammate
    ref = time_kiosk.person_reference

    [ @admin, kiosk ].each do |person|
      sign_in person.user

      [ :html, :turbo_stream ].each do |format|
        assert_difference -> { TimeClockPunch.where(person: @teammate, end_time: nil).count }, 1, "#{format} for #{person.user.email}" do
          post time_kiosk_path(format: format), params: { time_kiosk: { tool: "punch_in", person_ref: ref, time_clock_period_id: period.id } }
        end
        assert_response :success

        punch = TimeClockPunch.find_by!(person: @teammate, end_time: nil)
        patch time_kiosk_path(format: format), params: { time_kiosk: { tool: "punch_out", person_ref: ref, time_clock_punch_id: punch.id } }
        assert_response :success
        assert_not_nil punch.reload.end_time, "#{format} for #{person.user.email}"
      end
    end
  end

  # --- settings and theme ---------------------------------------------------

  test "admins open and save settings" do
    sign_in @admin.user

    get settings_path
    assert_response :success

    post update_settings_path, params: { settings: { infodump_day: Settings[:infodump_day] } }
    assert_redirected_to settings_path
  end

  test "a member can't open or change settings" do
    sign_in @member.user
    day = Settings[:infodump_day]

    get settings_path
    assert_redirected_to root_path

    post update_settings_path, params: { settings: { infodump_day: "Not #{day}" } }
    assert_redirected_to root_path
    assert_equal day, Settings[:infodump_day]
  end

  test "admins open and change the theme" do
    sign_in @admin.user

    get theme_path
    assert_response :success
    get edit_theme_path
    assert_response :success

    patch theme_path, params: { theme: { custom_css: "body { margin: 0; }" } }
    assert_redirected_to theme_path
    assert_equal "body { margin: 0; }", Theme.instance.custom_css
  end

  test "a member can't open or change the theme" do
    Theme.instance.update!(custom_css: "body { margin: 0; }")
    sign_in @member.user

    get theme_path
    assert_redirected_to root_path
    get edit_theme_path
    assert_redirected_to root_path

    patch theme_path, params: { theme: { custom_css: "body { display: none; }" } }
    assert_redirected_to root_path
    assert_equal "body { margin: 0; }", Theme.instance.reload.custom_css
  end

  # --- audit log --------------------------------------------------------------

  test "admins read the audit log, members don't" do
    page = Page.create!(title: "Handbook", content: "Hello", viewer: "user", editor: "admin")
    log = AuditLog.where(item: page).last

    sign_in @admin.user
    get audit_logs_path
    assert_response :success
    get audit_log_path(log)
    assert_response :success

    sign_in @member.user
    get audit_logs_path
    assert_redirected_to root_path
    get audit_log_path(log)
    assert_redirected_to root_path
  end

  test "an admin reverts an ordinary change, a member can't" do
    page = Page.create!(title: "Handbook", content: "Hello", viewer: "user", editor: "admin")
    page.update!(title: "Changed")
    log = AuditLog.where(item: page).order(:created_at).last

    sign_in @member.user
    post revert_audit_log_path(log)
    assert_redirected_to root_path
    assert_equal "Changed", page.reload.title

    sign_in @admin.user
    post revert_audit_log_path(log)
    assert_redirected_to audit_logs_url
    assert_equal "Handbook", page.reload.title
  end

  # --- API --------------------------------------------------------------------

  test "the user info API answers a token and refuses without one" do
    application = Doorkeeper::Application.create!(name: "App", redirect_uri: "https://example.com/callback", scopes: "user_read")
    token = Doorkeeper::AccessToken.create!(resource_owner_id: @member.user.id, application_id: application.id, scopes: "user_read", expires_in: 1.hour)

    get "/api/v1/userinfo", headers: { Authorization: "Bearer #{token.plaintext_token}" }
    assert_response :success
    assert_equal @member.user.neat_id, response.parsed_body["sub"]

    get "/api/v1/userinfo"
    assert_response :unauthorized
  end

  private

  def relationship_type
    @relationship_type ||= RelationshipType.create!(parent_label: "Parent", child_label: "Child", permission: :added_by_user)
  end

  def create_person(email, team: nil, admin: false)
    user = User.create!(email: email, password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: email.split("@").first.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team) if team
    person
  end
end
