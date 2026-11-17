require "test_helper"

class Mcp::EnvironmentTest < ActiveSupport::TestCase
  def with_environment(value, rails_env: "production")
    original = ENV["GP_ENVIRONMENT"]
    original_rails_env = Rails.env
    ENV["GP_ENVIRONMENT"] = value
    Rails.env = rails_env
    yield
  ensure
    ENV["GP_ENVIRONMENT"] = original
    Rails.env = original_rails_env
  end

  test "a production build is production unless it says otherwise" do
    with_environment(nil) { assert_equal "production", Mcp::Environment.current }
    with_environment("") { assert_equal "production", Mcp::Environment.current }
    with_environment("production") { assert_equal "production", Mcp::Environment.current }
  end

  test "a mistyped value counts as production" do
    with_environment("staging") { assert_equal "production", Mcp::Environment.current }
    with_environment("nonproduction") { assert_equal "production", Mcp::Environment.current }
  end

  test "non-production has to be said on a production build" do
    with_environment("non-production") { assert_equal "non-production", Mcp::Environment.current }
    with_environment(" Non-Production ") { assert_equal "non-production", Mcp::Environment.current }
  end

  test "a development or test build defaults to non-production, and can be set to production" do
    with_environment(nil, rails_env: "development") { assert_equal "non-production", Mcp::Environment.current }
    with_environment("production", rails_env: "development") { assert_equal "production", Mcp::Environment.current }
  end
end
