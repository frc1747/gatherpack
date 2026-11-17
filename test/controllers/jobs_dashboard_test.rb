require "test_helper"

class JobsDashboardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @admin = User.create!(email: "jobs-admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")

    @user_was, @password_was = MissionControl::Jobs.http_basic_auth_user, MissionControl::Jobs.http_basic_auth_password
    MissionControl::Jobs.http_basic_auth_user = "gatherpack"
    MissionControl::Jobs.http_basic_auth_password = "shared-jobs-password"

    # The test env uses the :test queue adapter, which Mission Control can't
    # read; point its server at SolidQueue, as production uses.
    @server = MissionControl::Jobs.applications.first.servers.first
    @adapter_was = @server.queue_adapter
    unless ActiveJob::QueueAdapters::SolidQueueAdapter < ActiveJob::QueueAdapters::SolidQueueExt
      ActiveJob::QueueAdapters::SolidQueueAdapter.prepend ActiveJob::QueueAdapters::SolidQueueExt
    end
    @server.instance_variable_set(:@queue_adapter, ActiveJob::QueueAdapters::SolidQueueAdapter.new)
  end

  teardown do
    @server.instance_variable_set(:@queue_adapter, @adapter_was)
    MissionControl::Jobs.http_basic_auth_user = @user_was
    MissionControl::Jobs.http_basic_auth_password = @password_was
  end

  test "a member cannot open the jobs dashboard even with the shared password" do
    sign_in users(:one)

    get "/jobs", headers: basic_auth
    follow_redirect! while response.redirect? && response.location.include?("/jobs")

    assert_not response.successful?, "A member (no role) opened Mission Control at /jobs (HTTP #{response.status}); only the shared basic password stands in the way"
    assert_redirected_to "/"
  end

  test "an admin with the shared password opens the jobs dashboard" do
    sign_in @admin

    get "/jobs", headers: basic_auth
    follow_redirect! while response.redirect? && response.location.include?("/jobs")

    assert_response :success
  end

  test "an admin still needs the shared password" do
    sign_in @admin

    get "/jobs"
    follow_redirect! while response.redirect? && response.location.include?("/jobs")

    assert_response :unauthorized
  end

  test "an anonymous visitor is sent to sign in" do
    get "/jobs", headers: basic_auth

    assert_redirected_to "/users/sign_in"
  end

  private

  def basic_auth
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("gatherpack", "shared-jobs-password") }
  end
end
