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

  def assert_invalid_scope
    assert_response :bad_request
    assert_includes response.body, I18n.t("doorkeeper.errors.messages.invalid_scope")
  end

  def code_from_redirect
    Rack::Utils.parse_query(URI(response.location).query).fetch("code")
  end

  def mcp_headers_for(token)
    { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }
  end

  def refresh_params(app, token, **extra)
    { grant_type: "refresh_token", refresh_token: token.refresh_token, client_id: app.uid, client_secret: app.plaintext_secret }.merge(extra)
  end

  def refreshable_token(app, scopes)
    Doorkeeper::AccessToken.create!(resource_owner_id: user(:alpha_member).id, application_id: app.id, scopes: scopes, expires_in: 2.hours, use_refresh_token: true)
  end

  # --- Which applications can ask for an MCP scope

  test "an application with blank scopes can't ask for an MCP scope" do
    blank = OauthApplication.create!(name: "Blank", redirect_uri: "https://client.example.com/callback", scopes: "", confidential: true)

    with_pkce_supported(false) do
      get "/oauth/authorize", params: authorize_params(blank, scope: "mcp_write")
      assert_invalid_scope

      assert_no_difference "Doorkeeper::AccessGrant.count" do
        post "/oauth/authorize", params: authorize_params(blank, scope: "mcp_write")
      end
      assert_invalid_scope

      get "/oauth/authorize", params: authorize_params(blank, scope: "user_read")
      assert_response :success
    end
  end

  test "an application whose scopes list only mcp_read can't ask for mcp_write" do
    app = OauthApplication.create!(name: "Read only", redirect_uri: "https://client.example.com/callback", scopes: "mcp_read", confidential: true)

    with_pkce_supported(false) do
      get "/oauth/authorize", params: authorize_params(app, scope: "mcp_read mcp_write")
      assert_invalid_scope

      get "/oauth/authorize", params: authorize_params(app, scope: "mcp_read")
      assert_response :success
    end
  end

  test "with the feature off, MCP scopes are refused and other scopes unchanged" do
    with_pkce_supported(false) do
      with_feature(:mcp, false) do
        get "/oauth/authorize", params: authorize_params(@confidential_app, scope: "mcp_read")
        assert_invalid_scope

        assert_no_difference "Doorkeeper::AccessGrant.count" do
          post "/oauth/authorize", params: authorize_params(@confidential_app, scope: "mcp_read")
        end
        assert_invalid_scope

        get "/oauth/authorize", params: authorize_params(@confidential_app, scope: "user_read")
        assert_response :success
      end
    end
  end

  # --- How scope reaches the check

  test "an omitted scope falls back to the default scope, or invalid_scope for an MCP-only application" do
    mcp_only = OauthApplication.create!(name: "MCP only", redirect_uri: "https://client.example.com/callback", scopes: "mcp_read", confidential: true)

    with_pkce_supported(false) do
      get "/oauth/authorize", params: authorize_params(@public_app, scope: "").except(:scope)
      assert_response :success
      assert_includes response.body, "Read your profile"
      assert_not_includes response.body, "AI assistant"

      get "/oauth/authorize", params: authorize_params(mcp_only, scope: "").except(:scope)
      assert_invalid_scope
    end
  end

  test "an array or hash scope is dropped and grants no MCP scope" do
    with_pkce_supported(false) do
      [ [ "mcp_read" ], { a: "mcp_read" } ].each do |scope|
        get "/oauth/authorize", params: authorize_params(@public_app, scope: scope)

        assert_response :success
        assert_includes response.body, "Read your profile"
        assert_not_includes response.body, "AI assistant"
      end
    end
  end

  # Rails merges query parameters over the body, and the check and Doorkeeper
  # both read params, so they can't be given different scopes.
  test "the check and the grant see the same scope when query and body differ" do
    with_pkce_supported(false) do
      assert_no_difference "Doorkeeper::AccessGrant.count" do
        post "/oauth/authorize?scope=mcp_read", params: authorize_params(@public_app, scope: "user_read")
      end
      assert_response :bad_request

      post "/oauth/authorize?scope=user_read", params: authorize_params(@public_app, scope: "mcp_read")
      assert_redirected_to(/code=/)
      assert_equal "user_read", Doorkeeper::AccessGrant.by_token(code_from_redirect).scopes.to_s
    end
  end

  # --- Refresh and code exchange can't widen

  test "a refresh keeps the token working on /mcp" do
    token = refreshable_token(@confidential_app, "mcp_read")

    post "/oauth/token", params: refresh_params(@confidential_app, token)
    assert_response :success
    assert_equal "mcp_read", response.parsed_body["scope"]

    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json, headers: mcp_headers_for(response.parsed_body["access_token"])
    assert_response :success
  end

  test "a refresh after the application's scopes are cleared gives no MCP access" do
    token = refreshable_token(@confidential_app, "mcp_write")
    @confidential_app.update!(scopes: "")

    post "/oauth/token", params: refresh_params(@confidential_app, token)
    assert_response :success

    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json, headers: mcp_headers_for(response.parsed_body["access_token"])
    assert_response :forbidden
  end

  test "a refresh can't widen to an MCP scope or to writes" do
    post "/oauth/token", params: refresh_params(@confidential_app, refreshable_token(@confidential_app, "user_read"), scope: "mcp_read")
    assert_response :bad_request
    assert_equal "invalid_scope", response.parsed_body["error"]

    post "/oauth/token", params: refresh_params(@confidential_app, refreshable_token(@confidential_app, "mcp_read"), scope: "mcp_write")
    assert_response :bad_request
    assert_equal "invalid_scope", response.parsed_body["error"]
  end

  test "a scope on the code exchange is ignored" do
    with_pkce_supported(false) do
      post "/oauth/authorize", params: authorize_params(@confidential_app, scope: "mcp_read")
      post "/oauth/token", params: { grant_type: "authorization_code", code: code_from_redirect, client_id: @confidential_app.uid,
        client_secret: @confidential_app.plaintext_secret, redirect_uri: @confidential_app.redirect_uri, scope: "mcp_write" }
    end

    assert_response :success
    assert_equal "mcp_read", response.parsed_body["scope"]
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

  test "supported: mcp_write can still be asked for while writes are off and not advertised" do
    with_settings(mcp_write_enabled: "false") do
      with_pkce_supported(true) do
        get "/oauth/authorize", params: authorize_params(@public_app, scope: "mcp_read mcp_write", **s256)
      end
    end

    assert_response :success
    assert_includes response.body, "Make changes in GatherPack through an AI assistant"
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
      code = code_from_redirect

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
