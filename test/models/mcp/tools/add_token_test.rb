require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::AddTokenTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  VALUE = "170000000034".freeze

  setup do
    host! "localhost"
    build_mcp_world
  end

  def add(viewer, holder, value = VALUE, **options)
    call_tool("add_token", user: user(viewer), person_id: person(holder).neat_id, value: value, **options)
  end

  test "an admin adds a token and gets it back masked" do
    result = add(:admin, :beta_member)

    token = Token.find_by!(value: VALUE)
    assert_equal person(:beta_member), token.tokenable
    assert_equal token, result.changed
    assert_equal({ "id" => token.neat_id, "person" => { "id" => person(:beta_member).neat_id, "name" => "BetaMember World" }, "masked_value" => "17••••••••34", "length" => 12 }, result.value)
    assert_equal user(:admin).id.to_s, token.versions.last.whodunnit
  end

  test "the call log stores the value masked: length, first two and last two" do
    add(:admin, :ward)
    assert_equal "17••••••••34", McpToolCall.order(:created_at).last.arguments["value"]

    add(:alpha_member, :ward, "990000000011")
    row = McpToolCall.order(:created_at).last
    assert_equal "denied", row.outcome
    assert_equal "99••••••••11", row.arguments["value"]
  end

  test "a value of four characters or fewer shows nothing, in the result and the log" do
    result = add(:admin, :ward, "1234")

    assert_equal "••••", result.value["masked_value"]
    assert_equal 4, result.value["length"]
    assert_equal "••••", McpToolCall.order(:created_at).last.arguments["value"]
    assert_equal "1234", result.changed.reload.value
  end

  test "a team manager adds one for their team's people" do
    assert_nil add(:alpha_manager, :ward).error
    assert_nil add(:alpha_manager, :alpha_manager, "990000000011").error
  end

  test "a plain member, even for themselves, gets Not allowed; someone out of sight is Not found" do
    assert_refused("Not allowed", Token, AuditLog) { add(:beta_member, :beta_member) }
    assert_refused("Not allowed", Token, AuditLog) { add(:beta_member, :badge_holder) }
    assert_refused("Not found", Token, AuditLog) { add(:beta_member, :ward) }
    assert_refused("Not found", Token, AuditLog) { add(:alpha_manager, :beta_member) }
  end

  test "a guardian can't reach their ward" do
    assert_refused("Not found", Token, AuditLog) { add(:guardian, :ward) }
    assert_refused("Not allowed", Token, AuditLog) { add(:guardian, :guardian) }
  end

  test "a duplicate is refused without saying whose it is" do
    Token.create!(tokenable: person(:badge_holder), value: VALUE)

    result = assert_refused("That value is already in use", Token, AuditLog) { add(:admin, :ward) }
    assert_not_includes result.error, "BadgeHolder"
    assert_not_includes result.to_response.to_h.to_json, "BadgeHolder"
  end

  test "a member can't use it to test a value" do
    Token.create!(tokenable: person(:badge_holder), value: VALUE)

    assert_refused("Not allowed", Token) { add(:beta_member, :beta_member) }
    assert_refused("Not allowed", Token) { add(:beta_member, :beta_member, "990000000011") }
  end

  test "a reader's other format of the same card is normalized before the duplicate check" do
    hex = "5700#{4660.to_s(16)}"

    result = add(:admin, :ward, hex)
    assert_equal "4660", result.changed.reload.value
    assert_equal "••••", result.value["masked_value"]
    assert_equal "••••", McpToolCall.order(:created_at).last.arguments["value"]

    assert_refused("That value is already in use", Token) { add(:admin, :ward, hex) }
    assert_refused("That value is already in use", Token) { add(:admin, :beta_member, "4660") }
  end

  test "bad input is refused cleanly" do
    assert_refused(/value/, Token) { call_tool("add_token", user: user(:admin), person_id: person(:ward).neat_id) }
    assert_refused(/.+/, Token) { add(:admin, :ward, 123456) }
    assert_refused(/line breaks/, Token) { add(:admin, :ward, "12345\n") }
    assert_refused(/line breaks/, Token) { add(:admin, :ward, "12\r345") }
    assert_refused(/NUL/, Token) { add(:admin, :ward, "12\u00003456") }
    assert_refused("Not found", Token) { call_tool("add_token", user: user(:admin), person_id: @beta.neat_id, value: VALUE) }
  end

  test "a tab is taken, as the page's input can send one" do
    assert_equal "11\t22", add(:admin, :ward, "11\t22").changed.reload.value
  end

  test "a value sent in the wrong type isn't stored in the log either" do
    add(:admin, :ward, 170000000034)

    assert_equal "17••••••••34", McpToolCall.order(:created_at).last.arguments["value"]
  end

  test "a read token and the setting being off refuse it, and so does the feature" do
    assert_refused("Not allowed", Token) { add(:admin, :ward, scopes: "mcp_read") }
    assert_refused("Writes disabled", Token) { add(:admin, :ward, writes_enabled: false) }
    with_feature(:tokens, false) { assert_refused("Feature off", Token) { add(:admin, :ward) } }
  end

  test "hooks run as they do on the page" do
    assert_hook_runs("tokens - create") { add(:admin, :ward) }
  end

  test "it allows and refuses as the page does" do
    Token.create!(tokenable: person(:badge_holder), value: "already-in-use")
    [
      [ :admin, :beta_member, VALUE ],
      [ :alpha_manager, :ward, VALUE ],
      [ :admin, :ward, "already-in-use" ],
      [ :beta_member, :beta_member, VALUE ],
      [ :guardian, :guardian, VALUE ],
      [ :admin, :ward, "" ]
    ].each do |viewer, holder, value|
      page = page_changes_rows?(Token, as: user(viewer)) do
        post tokens_path, params: { token: { tokenable_nid: person(holder).neat_id, value: value } }
      end
      tool = changes_rows?(Token) { add(viewer, holder, value) }

      assert_equal page, tool, "#{viewer} giving #{holder} #{value.inspect}"
    end
  end

  # The page looks a value up by its normalized form, so another format of the card is found.
  test "it refuses another format of a card already issued, as the page does" do
    Token.create!(tokenable: person(:badge_holder), value: "4660")
    hex = "5700#{4660.to_s(16)}"
    page = page_changes_rows?(Token, as: user(:admin)) do
      post tokens_path, params: { token: { tokenable_nid: person(:ward).neat_id, value: hex } }
    end

    assert_not page
    assert_refused("That value is already in use", Token) { add(:admin, :ward, hex) }
  end
end
