require "test_helper"
require_relative "../../support/mcp_world"

class Mcp::MetadataControllerTest < ActionDispatch::IntegrationTest
  include McpWorld

  setup { host! "localhost" }

  test "protected resource metadata" do
    [ "/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/mcp" ].each do |path|
      get path
      assert_response :success
      assert_equal({
        "resource" => "http://localhost/mcp",
        "authorization_servers" => [ "http://localhost" ],
        "scopes_supported" => %w[mcp_read mcp_write],
        "bearer_methods_supported" => [ "header" ]
      }, response.parsed_body)
    end
  end

  test "authorization server metadata" do
    get "/.well-known/oauth-authorization-server"
    assert_response :success
    json = response.parsed_body

    assert_equal "http://localhost", json["issuer"]
    assert_equal "http://localhost/oauth/authorize", json["authorization_endpoint"]
    assert_equal "http://localhost/oauth/token", json["token_endpoint"]
    assert_equal "http://localhost/oauth/revoke", json["revocation_endpoint"]
    assert_includes json["scopes_supported"], "mcp_read"
    assert_includes json["scopes_supported"], "mcp_write"
    assert_includes json["scopes_supported"], "user_read"
    assert_equal [ "code" ], json["response_types_supported"]
    assert_equal %w[authorization_code refresh_token], json["grant_types_supported"]
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
