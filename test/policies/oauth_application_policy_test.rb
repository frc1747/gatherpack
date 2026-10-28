require "test_helper"

class OauthApplicationPolicyTest < ActiveSupport::TestCase
  def test_scope
    application = OauthApplication.create!(name: "Wiki", redirect_uri: "https://wiki.example.com/oauth/callback", scopes: "user_read")

    assert OauthApplicationPolicy::Scope.new(User.new(admin: true), OauthApplication).resolve.exists?(application.id)
    assert_not OauthApplicationPolicy::Scope.new(User.new, OauthApplication).resolve.exists?(application.id)
  end

  def test_show
  end

  def test_create
  end

  def test_update
  end

  def test_destroy
  end
end
