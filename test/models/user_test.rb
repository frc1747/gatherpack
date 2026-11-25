require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "becoming a kiosk account revokes the access apps were given" do
    user = User.create!(email: "device@example.com", password: "Password1!")
    application = Doorkeeper::Application.create!(name: "App", redirect_uri: "https://example.com/callback", scopes: "user_read")
    token = Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application_id: application.id, scopes: "user_read", expires_in: 1.hour)
    grant = Doorkeeper::AccessGrant.create!(resource_owner_id: user.id, application_id: application.id, scopes: "user_read",
      expires_in: 10.minutes, redirect_uri: "https://example.com/callback")

    user.update!(kiosk: true)

    assert token.reload.revoked?, "an app authorized before the account became a kiosk still acts for it"
    assert grant.reload.revoked?
  end

  test "an admin flagged kiosk who loses admin has the access apps were given revoked" do
    user = User.create!(email: "device@example.com", password: "Password1!", admin: true, kiosk: true)
    application = Doorkeeper::Application.create!(name: "App", redirect_uri: "https://example.com/callback", scopes: "user_read")
    token = Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application_id: application.id, scopes: "user_read", expires_in: 1.hour)

    user.update!(admin: false)

    assert token.reload.revoked?, "an app authorized by the admin still acts for the kiosk account they became"
  end

  test "flagging an admin as a kiosk leaves the access apps were given alone" do
    user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    application = Doorkeeper::Application.create!(name: "App", redirect_uri: "https://example.com/callback", scopes: "user_read")
    token = Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application_id: application.id, scopes: "user_read", expires_in: 1.hour)

    user.update!(kiosk: true)

    assert_not token.reload.revoked?
  end

  test "other changes leave the access apps were given alone" do
    user = User.create!(email: "member@example.com", password: "Password1!", kiosk: true)
    application = Doorkeeper::Application.create!(name: "App", redirect_uri: "https://example.com/callback", scopes: "user_read")
    token = Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application_id: application.id, scopes: "user_read", expires_in: 1.hour)

    user.update!(kiosk: false)
    user.update!(email: "member2@example.com")

    assert_not token.reload.revoked?
  end
end
