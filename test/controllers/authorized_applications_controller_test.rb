require "test_helper"

class AuthorizedApplicationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @member = create_user("member@example.com")
    @other = create_user("other@example.com")
    @wiki = OauthApplication.create!(name: "Team Wiki", redirect_uri: "https://wiki.example.com/callback", scopes: "user_read")
    @chat = OauthApplication.create!(name: "Chat Room", redirect_uri: "https://chat.example.com/callback", scopes: "user_read")
    @member_token = create_token(@member, @wiki)
    @member_grant = Doorkeeper::AccessGrant.create!(resource_owner_id: @member.id, application_id: @wiki.id, scopes: "user_read",
                                                    redirect_uri: @wiki.redirect_uri, expires_in: 10.minutes)
    @other_token = create_token(@other, @chat)
  end

  test "a member can see and revoke the apps they authorized" do
    paths = Rails.application.routes.routes.map { |r| r.path.spec.to_s }
    assert paths.any? { |p| p.include?("authorized_applications") },
           "no route lets a member list or revoke the OAuth apps they authorized"
  end

  test "a member lists only the apps they authorized" do
    sign_in @member

    get authorized_applications_path

    assert_response :success
    assert_includes response.body, "Team Wiki"
    assert_not_includes response.body, "Chat Room"
  end

  test "a revoked app is no longer listed" do
    @member_token.revoke
    @member_grant.revoke
    sign_in @member

    get authorized_applications_path

    assert_response :success
    assert_not_includes response.body, "Team Wiki"
  end

  test "a member revokes an app's tokens and codes" do
    sign_in @member

    delete authorized_application_path(@wiki)

    assert_redirected_to authorized_applications_path
    assert @member_token.reload.revoked?
    assert @member_grant.reload.revoked?
    assert_not @other_token.reload.revoked?
  end

  test "a member can't revoke another member's app" do
    sign_in @member

    delete authorized_application_path(@chat)

    assert_response :not_found
    assert_not @other_token.reload.revoked?, "a member revoked another member's authorization"
  end

  test "revoking leaves the member's other access to the app with another member alone" do
    other_wiki_token = create_token(@other, @wiki)
    sign_in @member

    delete authorized_application_path(@wiki)

    assert_not other_wiki_token.reload.revoked?
  end

  test "a member's account page links to their authorized apps" do
    sign_in @member

    get edit_person_user_path(@member.person)

    assert_response :success
    assert_select "a[href=?]", authorized_applications_path
  end

  test "signing in is required" do
    get authorized_applications_path

    assert_redirected_to new_user_session_path
  end

  private

  def create_user(email)
    user = User.create!(email: email, password: "Password1!")
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    user
  end

  def create_token(user, app)
    Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application_id: app.id, scopes: "user_read",
                                    expires_in: 2.hours, use_refresh_token: true)
  end
end
