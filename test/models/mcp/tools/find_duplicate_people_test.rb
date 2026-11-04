require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::FindDuplicatePeopleTest < ActiveSupport::TestCase
  include McpWorld

  setup { build_mcp_world }

  def find(viewer, first_name: "Ward", last_name: "World", **options)
    call_tool("find_duplicate_people", user: user(viewer), first_name: first_name, last_name: last_name, **options)
  end

  def ids(result)
    result.value["items"].map { |item| item["id"] }
  end

  test "the same name, after trimming and case folding" do
    Person.create!(first_name: " WARD ", last_name: "world  ")
    Person.create!(first_name: "Ward", last_name: "Other")

    result = find(:admin, first_name: "  ward", last_name: "WORLD ")

    assert_equal 2, result.value["items"].size
    assert_includes ids(result), person(:ward).neat_id
    assert_equal [ %w[name] ], result.value["items"].map { |item| item["matched_on"] }.uniq
    assert_equal [ true, false ], result.value["items"].map { |item| item["has_login"] }.sort_by { |login| login ? 0 : 1 }
  end

  test "a name doesn't match as a pattern" do
    assert_empty ids(find(:admin, first_name: "W%", last_name: "World"))
  end

  test "the same login email gives has_login and never the email" do
    result = find(:admin, first_name: "Nobody", last_name: "Else", email: " WARD@example.com ")

    item = result.value["items"].sole
    assert_equal person(:ward).neat_id, item["id"]
    assert_equal %w[email], item["matched_on"]
    assert_equal true, item["has_login"]
    assert_not_includes result.value.to_json, "ward@example.com"
  end

  test "someone matching on both is listed once" do
    item = find(:admin, email: "ward@example.com").value["items"].sole

    assert_equal %w[name email], item["matched_on"]
  end

  test "a match outside the viewer's scope isn't revealed, by name or by email" do
    assert_empty ids(find(:beta_member))
    assert_empty ids(find(:beta_member, first_name: "Nobody", last_name: "Else", email: "ward@example.com"))
    assert_empty ids(find(:guardian, first_name: "Nobody", last_name: "Else", email: "ward@example.com"))
    assert_equal find(:beta_member, first_name: "Nobody", last_name: "Else", email: "nobody@example.com").value,
      find(:beta_member, first_name: "Nobody", last_name: "Else", email: "ward@example.com").value
  end

  test "a team manager and a teammate find people on their team" do
    assert_equal [ person(:ward).neat_id ], ids(find(:alpha_manager, email: "ward@example.com"))
    assert_equal [ person(:ward).neat_id ], ids(find(:alpha_member))
  end

  test "a login with no person is no match" do
    User.create!(email: "orphan@example.com", password: "Password1!")

    assert_empty ids(find(:admin, first_name: "Nobody", last_name: "Else", email: "orphan@example.com"))
  end

  test "blank names search by email only, and all blank is refused" do
    Person.create!(first_name: "", last_name: "")

    assert_equal [ person(:ward).neat_id ], ids(find(:admin, first_name: "", last_name: " ", email: "ward@example.com"))
    assert_equal "Give a name or an email", find(:admin, first_name: "", last_name: "").error
    assert_equal "Give a name or an email", find(:admin, first_name: "Ward", last_name: "", email: "").error
  end

  test "bad types and limits are refused, and the limit truncates" do
    assert_predicate find(:admin, first_name: 7), :error?
    assert_predicate find(:admin, limit: 1e400), :error?
    2.times { Person.create!(first_name: "Ward", last_name: "World") }
    result = find(:admin, limit: 2)
    assert_equal 2, result.value["items"].size
    assert_equal true, result.value["truncated"]
  end

  test "a read token is enough" do
    assert_not find(:admin, scopes: "mcp_read").error?
  end
end
