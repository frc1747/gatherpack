require "test_helper"

class AuthenticationRateLimitsTest < ActionDispatch::IntegrationTest
  PASSWORD = "Password1!"

  setup do
    host! "localhost"
    AuthenticationRateLimits.store = ActiveSupport::Cache::MemoryStore.new
    @admin = User.create!(email: "admin@example.com", password: PASSWORD, admin: true)
    @member = User.create!(email: "member@example.com", password: PASSWORD)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
    Person.create!(user: @member, first_name: "Max", last_name: "Member")
  end

  teardown do
    AuthenticationRateLimits.store = nil
  end

  test "repeated failed sign-ins are throttled or lock the account" do
    statuses = 50.times.map do |i|
      post user_session_path, params: { user: { email: @admin.email, password: "wrong-guess-#{i}" } }
      response.status
    end
    throttled = statuses.include?(429)

    post user_session_path, params: { user: { email: @admin.email, password: PASSWORD } }
    signed_in = response.redirect? && response.location !~ /sign_in/

    assert throttled || !signed_in,
      "50 wrong passwords for the admin were accepted for checking (statuses #{statuses.tally}), " \
      "then the right password signed in: no throttling and no lockout"
  end

  test "sign-in from one address is throttled" do
    statuses = 21.times.map do
      post user_session_path, params: { user: { email: "nobody-#{SecureRandom.hex(4)}@example.com", password: "guess" } }
      response.status
    end

    assert_equal [ 422 ] * 20 + [ 429 ], statuses
    assert_match "Too many attempts", response.body
  end

  test "too many wrong passwords lock the account until unlock_in has passed" do
    AuthenticationRateLimits.store = nil
    Devise.maximum_attempts.times do |i|
      post user_session_path, params: { user: { email: @admin.email, password: "wrong-guess-#{i}" } }
    end

    post user_session_path, params: { user: { email: @admin.email, password: PASSWORD } }
    assert_response :unprocessable_entity, "the right password signed in to a locked account"

    travel Devise.unlock_in + 1.minute do
      post user_session_path, params: { user: { email: @admin.email, password: PASSWORD } }
      assert_redirected_to root_path
    end
  end

  test "one account's lockout doesn't lock another account signing in from the same address" do
    AuthenticationRateLimits.store = nil
    Devise.maximum_attempts.times do |i|
      post user_session_path, params: { user: { email: @admin.email, password: "wrong-guess-#{i}" } }
    end
    assert @admin.reload.locked_at, "precondition: the admin's account is locked"

    post user_session_path, params: { user: { email: @member.email, password: PASSWORD } }

    assert_redirected_to root_path
  end

  test "a lock doesn't end a session that is already signed in" do
    owner = open_session
    owner.host! "localhost"
    owner.post user_session_path, params: { user: { email: @admin.email, password: PASSWORD } }
    owner.get people_path
    owner.assert_response :success

    AuthenticationRateLimits.store = nil
    Devise.maximum_attempts.times do |i|
      post user_session_path, params: { user: { email: @admin.email, password: "wrong-guess-#{i}" } }
    end
    assert @admin.reload.access_locked?, "precondition: the admin's account is locked"

    owner.get people_path
    owner.assert_response :success
  end

  test "a lock doesn't refuse sign-in through a provider" do
    @admin.update_columns(provider: "github", uid: "12345", locked_at: Time.current, failed_attempts: Devise.maximum_attempts)
    auth = OmniAuth::AuthHash.new(provider: "github", uid: "12345", info: { email: @admin.email })

    get user_github_omniauth_callback_path, env: { "omniauth.auth" => auth }

    assert_redirected_to root_path
    get people_path
    assert_response :success
  end

  test "sign-in for one account is throttled across addresses" do
    statuses = 11.times.map do |i|
      @admin.update_columns(failed_attempts: 0)
      post user_session_path, params: { user: { email: @admin.email, password: "wrong-guess-#{i}" } }, env: { "REMOTE_ADDR" => "203.0.113.#{i + 1}" }
      response.status
    end

    assert_equal [ 422 ] * 10 + [ 429 ], statuses
  end

  test "counting and clearing failed sign-ins doesn't write audit entries" do
    AuthenticationRateLimits.store = nil

    assert_no_difference -> { AuditLog.where(item: @admin).count } do
      post user_session_path, params: { user: { email: @admin.email, password: "wrong" } }
      post user_session_path, params: { user: { email: @admin.email, password: PASSWORD } }
    end
    assert_equal 0, @admin.reload.failed_attempts
  end

  test "password reset requests are throttled" do
    statuses = 50.times.map do
      post user_password_path, params: { user: { email: @admin.email } }
      response.status
    end

    assert_includes statuses, 429,
      "50 password-reset requests for one account were all processed (statuses #{statuses.tally}): " \
      "no rate limit, so anyone can mail-bomb a member"
  end

  test "password reset requests for one account are throttled across addresses" do
    statuses = 6.times.map do |i|
      post user_password_path, params: { user: { email: " #{@member.email.upcase} " } }, env: { "REMOTE_ADDR" => "203.0.113.#{i + 1}" }
      response.status
    end

    assert_equal 429, statuses.last, "statuses #{statuses.inspect}"
    assert_not_includes statuses.first(5), 429
  end

  test "sign-ups are throttled" do
    statuses = 11.times.map do |i|
      post user_registration_path, params: { user: { email: "new-#{i}@example.com", password: PASSWORD, password_confirmation: "mismatch" } }
      response.status
    end

    assert_equal 429, statuses.last, "statuses #{statuses.inspect}"
  end
end
