require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::RemoveTokenTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @ward_token = Token.create!(tokenable: person(:ward), value: "170000000034")
    @beta_token = Token.create!(tokenable: person(:beta_member), value: "990000000011")
  end

  def remove(viewer, token, **options)
    call_tool("remove_token", user: user(viewer), token_id: token.neat_id, **options)
  end

  test "an admin removes one and gets it back masked" do
    result = nil
    assert_difference("Token.count", -1) { result = remove(:admin, @ward_token) }

    assert_equal "17••••••••34", result.value["masked_value"]
    assert_equal true, result.value["removed"]
    assert_equal person(:ward).neat_id, result.value.dig("person", "id")
    assert_not_includes result.value.to_json, "170000000034"
  end

  test "a team manager removes one from their team's people, and can't see another team's" do
    assert_difference("Token.count", -1) { assert_nil remove(:alpha_manager, @ward_token).error }
    assert_refused("Not found", Token, AuditLog) { remove(:alpha_manager, @beta_token) }
  end

  test "a plain member sees their own but can't remove it, and can't see another's" do
    assert_refused("Not allowed", Token, AuditLog) { remove(:beta_member, @beta_token) }
    assert_refused("Not found", Token, AuditLog) { remove(:beta_member, @ward_token) }
  end

  test "a guardian can't reach their ward's" do
    assert_refused("Not found", Token, AuditLog) { remove(:guardian, @ward_token) }
  end

  test "a token held by something other than a person comes back with no person" do
    hook = Hook.create!(name: "Door", event: "token - activate", code: "nil")
    token = Token.create!(tokenable: hook, value: "880000000022")

    result = remove(:admin, token)
    assert_nil result.value["person"]
    assert_equal "88••••••••22", result.value["masked_value"]
  end

  test "a read token and the setting being off refuse it, and a bad ID is not found" do
    assert_refused("Not allowed", Token) { remove(:admin, @ward_token, scopes: "mcp_read") }
    assert_refused("Writes disabled", Token) { remove(:admin, @ward_token, writes_enabled: false) }
    with_feature(:tokens, false) { assert_refused("Feature off", Token) { remove(:admin, @ward_token) } }
    assert_refused("Not found", Token) { call_tool("remove_token", user: user(:admin), token_id: "tok_nonsense") }
  end

  test "hooks run as they do on the page" do
    assert_hook_runs("tokens - destroy") { remove(:admin, @ward_token) }
  end

  test "it allows and refuses as the page does" do
    [
      [ :admin, @beta_token ],
      [ :alpha_manager, @ward_token ],
      [ :alpha_manager, @beta_token ],
      [ :beta_member, @beta_token ],
      [ :guardian, @ward_token ]
    ].each do |viewer, token|
      page = page_changes_rows?(Token, as: user(viewer)) { delete token_path(token) }
      tool = changes_rows?(Token) { remove(viewer, token) }

      assert_equal page, tool, "#{viewer} removing #{token.neat_id}"
    end
  end
end
