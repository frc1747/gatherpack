require "test_helper"

class KioskSessionTest < ActionDispatch::IntegrationTest
  PASSWORD = "Password1!"

  setup do
    host! "localhost"
    @team = Team.create!(name: "Robotics", team_type: team_types(:one))
    @kiosk_user, @kiosk = create_person("kiosk", team: @team)
    _, @member = create_person("member", team: @team)
    @admin_user, = create_person("admin", admin: true)
  end

  test "a kiosk account cannot browse the people directory" do
    make_kiosk(@kiosk_user)
    sign_in_with_password(@kiosk_user)

    get time_kiosk_path
    assert_response :success

    get people_path

    assert_not response.successful? && response.body.include?(@member.last_name),
      "the kiosk account (left signed in on a shared screen) lists members at /people"
    assert_redirected_to time_kiosk_path
  end

  test "a kiosk account is kept to the kiosk" do
    make_kiosk(@kiosk_user)
    sign_in_with_password(@kiosk_user)

    [ root_path, person_path(@member), edit_person_user_path(@kiosk), settings_path ].each do |path|
      get path
      assert_redirected_to time_kiosk_path, path
    end

    post stop_impersonating_people_path
    assert_redirected_to time_kiosk_path

    get people_path, as: :json
    assert_response :forbidden
    post people_path, headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }
    assert_response :forbidden
  end

  test "a kiosk account can't open the jobs dashboard" do
    make_kiosk(@kiosk_user)
    sign_in_with_password(@kiosk_user)

    get "/jobs"

    # Compared as a string: after a request to an engine, the test's own
    # route helpers put the engine's mount point in front.
    assert_response :see_other
    assert_equal "http://localhost/time_kiosk", response.location
  end

  test "a kiosk account can't upload files directly" do
    make_kiosk(@kiosk_user)
    sign_in_with_password(@kiosk_user)
    body = "%PDF-1.4 a receipt"

    assert_no_difference -> { ActiveStorage::Blob.count }, "a kiosk account created a direct-upload blob" do
      post rails_direct_uploads_path, as: :json, params: { blob: {
        filename: "receipt.pdf", byte_size: body.bytesize, checksum: Digest::MD5.base64digest(body), content_type: "application/pdf"
      } }
    end
    assert_response :forbidden
  end

  test "a kiosk account can't open file downloads or its authorized apps" do
    make_kiosk(@kiosk_user)
    sign_in_with_password(@kiosk_user)

    get ledger_ledger_entry_receipt_path("led_x", "le_x", "x")
    assert_redirected_to time_kiosk_path

    get authorized_applications_path
    assert_redirected_to time_kiosk_path
  end

  test "a kiosk account can't authorize an app to act for it" do
    application = Doorkeeper::Application.create!(name: "App", redirect_uri: "https://example.com/callback", scopes: "user_read")
    make_kiosk(@kiosk_user)
    sign_in_with_password(@kiosk_user)

    get oauth_authorization_path(client_id: application.uid, redirect_uri: application.redirect_uri, response_type: "code", scope: "user_read")

    assert_redirected_to time_kiosk_path
    assert_empty Doorkeeper::AccessGrant.where(resource_owner_id: @kiosk_user.id)
  end

  test "the kiosk page has no link out of the kiosk for a kiosk account" do
    make_kiosk(@kiosk_user)
    sign_in_with_password(@kiosk_user)

    get time_kiosk_path

    assert_select "a.navbar-brand[href=?]", time_kiosk_path
    assert_select "a[href='/']", count: 0
  end

  test "a kiosk account can sign out from the kiosk" do
    make_kiosk(@kiosk_user)
    sign_in_with_password(@kiosk_user)

    get time_kiosk_path
    assert_select "form[action=?] input[name=_method][value=delete]", destroy_user_session_path
    delete destroy_user_session_path
    get time_kiosk_path

    assert_redirected_to new_user_session_path
  end

  test "a kiosk account is signed out after its idle timeout" do
    make_kiosk(@kiosk_user)
    sign_in_with_password(@kiosk_user)

    travel User::KIOSK_TIMEOUT - 1.minute do
      get time_kiosk_path
      assert_response :success
    end

    travel User::KIOSK_TIMEOUT * 2 do
      get time_kiosk_path
      assert_equal "Your session expired. Please sign in again to continue.", flash[:alert]
    end
  end

  test "a kiosk account is not remembered" do
    make_kiosk(@kiosk_user)

    sign_in_with_password(@kiosk_user, remember_me: "1")

    assert cookies["remember_user_token"].blank?, "a remember-me cookie was issued to a kiosk account"
  end

  test "a remember-me cookie from before the account became a kiosk doesn't outlast the kiosk timeout" do
    sign_in_with_password(@kiosk_user, remember_me: "1")
    assert cookies["remember_user_token"].present?, "precondition: remember-me cookie present"
    make_kiosk(@kiosk_user)

    travel User::KIOSK_TIMEOUT * 2 do
      get time_kiosk_path
      assert_response :redirect
      follow_redirect!
      assert_redirected_to new_user_session_path
    end
  end

  test "an admin who is also a kiosk account isn't kept to the kiosk" do
    make_kiosk(@admin_user)
    sign_in_with_password(@admin_user)

    get people_path
    assert_response :success

    get time_kiosk_path
    assert_select "a.navbar-brand[href='/']"
  end

  test "an admin impersonating a kiosk account can stop" do
    make_kiosk(@kiosk_user)
    sign_in_with_password(@admin_user)
    post impersonate_person_path(@kiosk)

    get people_path
    assert_redirected_to time_kiosk_path

    follow_redirect!
    assert_select "form[action=?] button", stop_impersonating_people_path, text: "Stop Impersonating"
    post stop_impersonating_people_path
    get people_path
    assert_response :success
  end

  private

  def make_kiosk(user)
    user.update!(kiosk: true)
  end

  def sign_in_with_password(user, remember_me: "0")
    post user_session_path, params: { user: { email: user.email, password: PASSWORD, remember_me: remember_me } }
    assert_redirected_to root_path
  end

  def create_person(name, team: nil, admin: false)
    user = User.create!(email: "#{name}@example.com", password: PASSWORD, admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "#{name.capitalize}son")
    Membership.create!(person: person, team: team) if team
    [ user, person ]
  end
end
