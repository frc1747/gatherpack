require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListTokensTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    @ward_token = Token.create!(tokenable: person(:ward), value: "170000000034")
    @beta_token = Token.create!(tokenable: person(:beta_member), value: "990000000011")
  end

  def tokens(viewer, holder, **options)
    call_tool("list_tokens", user: user(viewer), person_id: person(holder).neat_id, **options)
  end

  test "an admin sees a person's tokens, masked with a clue, never in full" do
    result = tokens(:admin, :ward)

    assert_equal [ { "id" => @ward_token.neat_id, "person" => { "id" => person(:ward).neat_id, "name" => "Ward World" }, "masked_value" => "17••••••••34", "length" => 12 } ], result.value["items"]
    assert_not_includes result.value.to_json, "170000000034"
  end

  test "a team manager sees those of their teams' people; a member only their own" do
    assert_equal [ @ward_token.neat_id ], tokens(:alpha_manager, :ward).value["items"].map { |item| item["id"] }
    assert_equal [ @beta_token.neat_id ], tokens(:beta_member, :beta_member).value["items"].map { |item| item["id"] }
    assert_empty tokens(:alpha_member, :ward).value["items"]
  end

  test "a plain member on another team and a guardian can't reach the person" do
    assert_equal "Not found", tokens(:beta_member, :ward).error
    assert_equal "Not found", tokens(:guardian, :ward).error
    assert_equal "Not found", tokens(:alpha_manager, :beta_member).error
  end

  test "values of four characters or fewer show nothing but their length" do
    {
      "1" => "•", "12" => "••", "123" => "•••", "1234" => "••••", "12345" => "12•45", "" => ""
    }.each { |value, masked| assert_equal masked, Mcp::TokenRecords.masked(value), value }

    short = Token.create!(tokenable: person(:ward), value: "1234")
    item = tokens(:admin, :ward).value["items"].find { |candidate| candidate["id"] == short.neat_id }
    assert_equal "••••", item["masked_value"]
    assert_equal 4, item["length"]
  end

  test "the feature being off refuses it" do
    with_feature(:tokens, false) { assert_equal "Feature off", tokens(:admin, :ward).error }
  end
end
