require "test_helper"
require_relative "../support/mcp_world"

class McpPkceTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  CHALLENGE = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

  setup do
    host! "localhost"
    build_mcp_world
    sign_in user(:alpha_member)
    @public_app = create_app("Public Client", confidential: false)
    @confidential_app = create_app("Confidential Client", confidential: true)
  end

  def create_app(name, confidential:)
    OauthApplication.create!(name: name, redirect_uri: "https://client.example.com/callback",
      scopes: "mcp_read mcp_write user_read", confidential: confidential)
  end

  def authorize_params(app, scope:, **extra)
    { client_id: app.uid, redirect_uri: app.redirect_uri, response_type: "code", scope: scope, state: "s" }.merge(extra)
  end

  def s256
    { code_challenge: CHALLENGE, code_challenge_method: "S256" }
  end

  # --- Grants table without PKCE columns

  test "unsupported: a public client asking for an MCP scope is refused" do
    with_pkce_supported(false) do
      get "/oauth/authorize", params: authorize_params(@public_app, scope: "mcp_read")
      assert_response :bad_request
      assert_includes response.body, "confidential clients"

      get "/oauth/authorize", params: authorize_params(@public_app, scope: "user_read mcp_write", **s256)
      assert_response :bad_request

      assert_no_difference "Doorkeeper::AccessGrant.count" do
        post "/oauth/authorize", params: authorize_params(@public_app, scope: "mcp_read")
      end
      assert_response :bad_request
    end
  end

  test "unsupported: a confidential client asking for an MCP scope reaches the consent page in plain words" do
    with_pkce_supported(false) do
      get "/oauth/authorize", params: authorize_params(@confidential_app, scope: "mcp_read mcp_write")
    end

    assert_response :success
    assert_includes response.body, "Read your GatherPack data through an AI assistant"
    assert_includes response.body, "Make changes in GatherPack through an AI assistant"
  end

  test "unsupported: non-MCP requests are unchanged" do
    with_pkce_supported(false) do
      [ @public_app, @confidential_app ].each do |app|
        get "/oauth/authorize", params: authorize_params(app, scope: "user_read")
        assert_response :success
        assert_includes response.body, "Read your profile"
      end
    end
  end

  test "unsupported: an unknown client gets Doorkeeper's own error" do
    with_pkce_supported(false) do
      get "/oauth/authorize", params: { client_id: "nope", redirect_uri: "https://client.example.com/callback", response_type: "code", scope: "mcp_read" }
    end

    assert_not_includes response.body, "confidential clients"
    assert_includes response.body, I18n.t("doorkeeper.errors.messages.invalid_client")
  end

  # --- Grants table with PKCE columns (stubbed: no grant is created here)

  test "supported: an MCP request without a challenge is refused, public or confidential" do
    with_pkce_supported(true) do
      [ @public_app, @confidential_app ].each do |app|
        get "/oauth/authorize", params: authorize_params(app, scope: "mcp_read")
        assert_response :bad_request
        assert_includes response.body, "PKCE"
      end
    end
  end

  test "supported: the plain method is refused" do
    with_pkce_supported(true) do
      get "/oauth/authorize", params: authorize_params(@public_app, scope: "mcp_read", code_challenge: CHALLENGE, code_challenge_method: "plain")
    end

    assert_response :bad_request
  end

  test "supported: the consent POST can't skip the check" do
    with_pkce_supported(true) do
      assert_no_difference "Doorkeeper::AccessGrant.count" do
        post "/oauth/authorize", params: authorize_params(@public_app, scope: "mcp_write")
      end
    end

    assert_response :bad_request
  end

  test "supported: S256 reaches the consent page, whose form keeps the challenge" do
    with_pkce_supported(true) do
      get "/oauth/authorize", params: authorize_params(@public_app, scope: "mcp_read", **s256)
    end

    assert_response :success
    assert_select "form[method=post] input[name=code_challenge][value=?]", CHALLENGE
    assert_select "form[method=post] input[name=code_challenge_method][value=S256]"
  end

  test "supported: non-MCP requests are unchanged" do
    with_pkce_supported(true) do
      [ @public_app, @confidential_app ].each do |app|
        get "/oauth/authorize", params: authorize_params(app, scope: "user_read")
        assert_response :success
      end
    end
  end

  # --- Getting a token

  test "a confidential client's code exchange gives a token that works on /mcp" do
    with_pkce_supported(false) do
      post "/oauth/authorize", params: authorize_params(@confidential_app, scope: "mcp_read")
      code = Rack::Utils.parse_query(URI(response.location).query).fetch("code")

      post "/oauth/token", params: { grant_type: "authorization_code", code: code, client_id: @confidential_app.uid,
        client_secret: @confidential_app.plaintext_secret, redirect_uri: @confidential_app.redirect_uri }
      assert_response :success
    end
    token = response.parsed_body.fetch("access_token")

    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "whoami" } }.to_json,
      headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }
    assert_response :success
    assert_equal person(:alpha_member).neat_id, response.parsed_body.dig("result", "structuredContent", "person", "id")
  end

  # client_credentials is an enabled grant flow, so Doorkeeper issues this token;
  # it has no resource owner, so /mcp refuses it.
  test "a client_credentials token with an MCP scope doesn't work on /mcp" do
    sign_out user(:alpha_member)
    post "/oauth/token", params: { grant_type: "client_credentials", client_id: @confidential_app.uid,
      client_secret: @confidential_app.plaintext_secret, scope: "mcp_read" }
    assert_response :success
    token = response.parsed_body.fetch("access_token")
    assert_nil Doorkeeper::AccessToken.by_token(token).resource_owner_id

    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
      headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }
    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], %(error="invalid_token")
  end

  test "the password grant isn't available" do
    post "/oauth/token", params: { grant_type: "password", client_id: @confidential_app.uid, client_secret: @confidential_app.plaintext_secret,
      username: user(:alpha_member).email, password: "Password1!", scope: "mcp_read" }

    assert_response :bad_request
    assert_equal "unsupported_grant_type", response.parsed_body["error"]
  end

  test "the new scopes show on the OAuth Applications form" do
    sign_out user(:alpha_member)
    sign_in user(:admin)
    get new_oauth_application_path

    assert_response :success
    assert_includes response.body, "mcp_read"
    assert_includes response.body, "mcp_write"
  end
end
