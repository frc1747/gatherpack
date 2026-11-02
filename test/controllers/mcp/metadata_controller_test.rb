require "test_helper"
require_relative "../../support/mcp_world"

class Mcp::MetadataControllerTest < ActionDispatch::IntegrationTest
  include McpWorld

  setup { host! "localhost" }

  def assert_protected_resource_scopes(scopes)
    [ "/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/mcp" ].each do |path|
      get path
      assert_response :success
      assert_equal({
        "resource" => "http://localhost/mcp",
        "authorization_servers" => [ "http://localhost" ],
        "scopes_supported" => scopes,
        "bearer_methods_supported" => [ "header" ]
      }, response.parsed_body)
    end
  end

  def authorization_server_scopes
    get "/.well-known/oauth-authorization-server"
    assert_response :success
    response.parsed_body["scopes_supported"]
  end

  test "protected resource metadata advertises both scopes while writes are on" do
    with_settings(mcp_write_enabled: "true") { assert_protected_resource_scopes(%w[mcp_read mcp_write]) }
  end

  test "protected resource metadata advertises only mcp_read while writes are off" do
    with_settings(mcp_write_enabled: "false") { assert_protected_resource_scopes(%w[mcp_read]) }
  end

  test "authorization server metadata" do
    get "/.well-known/oauth-authorization-server"
    assert_response :success
    json = response.parsed_body

    assert_equal "http://localhost", json["issuer"]
    assert_equal "http://localhost/oauth/authorize", json["authorization_endpoint"]
    assert_equal "http://localhost/oauth/token", json["token_endpoint"]
    assert_equal "http://localhost/oauth/revoke", json["revocation_endpoint"]
    assert_equal [ "code" ], json["response_types_supported"]
    assert_equal %w[authorization_code refresh_token], json["grant_types_supported"]
  end

  test "authorization server metadata advertises every scope while writes are on" do
    with_settings(mcp_write_enabled: "true") do
      assert_equal Doorkeeper.config.scopes.to_a, authorization_server_scopes
      assert_includes authorization_server_scopes, "mcp_read"
      assert_includes authorization_server_scopes, "mcp_write"
      assert_includes authorization_server_scopes, "user_read"
    end
  end

  test "authorization server metadata leaves out only mcp_write while writes are off" do
    with_settings(mcp_write_enabled: "false") do
      assert_equal Doorkeeper.config.scopes.to_a - [ "mcp_write" ], authorization_server_scopes
      assert_includes authorization_server_scopes, "mcp_read"
      assert_includes authorization_server_scopes, "user_read"
    end
  end

  test "without PKCE support, neither PKCE nor public clients are advertised" do
    with_pkce_supported(false) do
      get "/.well-known/oauth-authorization-server"
    end
    json = response.parsed_body

    assert_not json.key?("code_challenge_methods_supported")
    assert_equal %w[client_secret_post client_secret_basic], json["token_endpoint_auth_methods_supported"]
  end

  test "with PKCE support, S256 and public clients are advertised" do
    with_pkce_supported(true) do
      get "/.well-known/oauth-authorization-server"
    end
    json = response.parsed_body

    assert_equal [ "S256" ], json["code_challenge_methods_supported"]
    assert_equal %w[client_secret_post client_secret_basic none], json["token_endpoint_auth_methods_supported"]
  end

  test "both 404 when the feature is off" do
    with_feature(:mcp, false) do
      [ "/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/mcp", "/.well-known/oauth-authorization-server" ].each do |path|
        get path
        assert_response :not_found
      end
    end
  end
end
