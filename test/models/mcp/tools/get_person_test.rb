require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::GetPersonTest < ActiveSupport::TestCase
  include McpWorld

  setup { build_mcp_world }

  def get(viewer, target)
    call_tool("get_person", user: user(viewer), person_id: person(target).neat_id)
  end

  # Other initializers may have registered extensions: put them back.
  setup { @saved_extensions = Mcp.person_extensions.dup }
  teardown { Mcp.person_extensions.replace(@saved_extensions) }

  test "an admin sees the profile, contact details, teams, badges and relationships" do
    person(:ward).update!(phone_number: "555-0100", address: "1 Main St", birthday: Date.new(2012, 5, 6), shirt_size: "M")
    value = get(:admin, :ward).value

    assert_equal person(:ward).neat_id, value["id"]
    assert_equal "Ward World", value["name"]
    assert_equal "ward@example.com", value["email"]
    assert_equal [ "555-0100", "1 Main St", "2012-05-06", "M" ], value.values_at("phone_number", "address", "birthday", "shirt_size")
    assert_equal [ { "id" => @alpha.neat_id, "name" => "Alpha", "manager" => false } ], value["teams"]
    assert_equal [], value["badges"]
    assert_equal [ { "label" => "Parent of", "person" => { "id" => person(:guardian).neat_id, "name" => "Guardian World" } } ],
      value["relationships"]
  end

  test "a team manager sees a member, and the manager flag" do
    assert_equal "alphamember@example.com", get(:alpha_manager, :alpha_member).value["email"]
    assert_equal [ true ], get(:alpha_manager, :alpha_manager).value["teams"].map { |team| team["manager"] }
  end

  test "a member sees a teammate and themselves" do
    assert_equal "Ward World", get(:alpha_member, :ward).value["name"]
    assert_equal "AlphaMember World", get(:alpha_member, :alpha_member).value["name"]
  end

  test "a member on another team can't find someone outside their teams" do
    assert_equal "Not found", get(:beta_member, :alpha_member).error
    assert_equal :error, get(:beta_member, :alpha_member).outcome
  end

  test "a guardian sees their own profile with the ward, but not the ward's profile" do
    assert_equal [ { "label" => "Child of", "person" => { "id" => person(:ward).neat_id, "name" => "Ward World" } } ],
      get(:guardian, :guardian).value["relationships"]
    assert_equal "Not found", get(:guardian, :ward).error
  end

  test "relationships outside the viewer's scope are left out" do
    assert_empty get(:alpha_member, :ward).value["relationships"]
  end

  test "teams the viewer can't see are left out" do
    @beta.update!(join_permission: :added_by_admin)
    Membership.create!(person: person(:alpha_member), team: @beta)

    assert_equal [ @alpha.neat_id ], get(:alpha_manager, :alpha_member).value["teams"].map { |team| team["id"] }
    assert_equal [ @alpha.neat_id, @beta.neat_id ].sort, get(:admin, :alpha_member).value["teams"].map { |team| team["id"] }.sort
  end

  test "badges are listed only for badges the viewer can see, and only with the badges feature" do
    Membership.create!(person: person(:beta_member), team: @alpha)
    BadgeAssignment.create!(badge: @access_badge, person: person(:beta_member))
    team_badge = create_world_badge("Beta Badge", team: @beta)
    BadgeAssignment.create!(badge: team_badge, person: person(:beta_member))

    assert_equal [ "Beta Badge", "MCP Access" ], get(:admin, :beta_member).value["badges"].map { |badge| badge["name"] }
    assert_equal [ "MCP Access" ], get(:alpha_manager, :beta_member).value["badges"].map { |badge| badge["name"] }
    with_feature(:badges, false) { assert_not get(:admin, :beta_member).value.key?("badges") }
  end

  test "a person without a user has no email" do
    Person.create!(first_name: "No", last_name: "User")
    nobody = Person.find_by!(first_name: "No")

    assert_nil call_tool("get_person", user: user(:admin), person_id: nobody.neat_id).value["email"]
  end

  test "a person with no display name is named by their names, then their ID" do
    solo = Person.create!(first_name: "Solo")
    nameless = Person.create!
    Membership.create!(person: solo, team: @alpha)
    Membership.create!(person: nameless, team: @alpha)

    assert_equal "Solo", call_tool("get_person", user: user(:admin), person_id: solo.neat_id).value["name"]
    assert_equal nameless.neat_id, call_tool("get_person", user: user(:admin), person_id: nameless.neat_id).value["name"]
    members = call_tool("get_team", user: user(:admin), team_id: @alpha.neat_id).value["members"]
    assert_includes members.map { |member| member["name"] }, "Solo"
    assert_includes members.map { |member| member["name"] }, nameless.neat_id
  end

  test "an extension whose value fails to serialize, or that raises a ScriptError, is dropped" do
    exploding = Object.new
    def exploding.as_json(*) = raise("no json")
    Mcp.person_extensions << ->(_subject, _viewer) { { lazy: Person.where("no_such_column = 1") } }
    Mcp.person_extensions << ->(_subject, _viewer) { { bad: exploding } }
    Mcp.person_extensions << ->(_subject, _viewer) { raise NotImplementedError, "later" }
    Mcp.person_extensions << ->(_subject, _viewer) { { blob: "\xFF".b.force_encoding("UTF-8") } }
    Mcp.person_extensions << ->(_subject, _viewer) { { extra: true } }
    result = get(:admin, :ward)

    assert_nil result.error
    assert_equal [ true, "Ward World" ], result.value.values_at("extra", "name")
    assert_not result.value.key?("lazy")
    assert_not result.value.key?("bad")
    assert_not result.value.key?("blob")
    assert_nothing_raised { result.to_response }
  end

  test "a wrong ID prefix or a malformed ID is not found" do
    assert_equal "Not found", call_tool("get_person", user: user(:admin), person_id: @alpha.neat_id).error
    assert_equal "Not found", call_tool("get_person", user: user(:admin), person_id: "nonsense").error
  end

  test "an extension's keys are added and can't replace the profile's own" do
    seen = []
    Mcp.person_extensions << ->(subject, viewer) { seen << [ subject, viewer ]; { fields: { "example_key" => "example" }, name: "Hijacked" } }
    value = get(:alpha_manager, :ward).value

    assert_equal({ "example_key" => "example" }, value["fields"])
    assert_equal "Ward World", value["name"]
    assert_equal [ [ person(:ward), person(:alpha_manager) ] ], seen
  end

  test "an extension is not called when the viewer can't see the person" do
    called = false
    Mcp.person_extensions << ->(_subject, _viewer) { called = true; {} }
    get(:beta_member, :alpha_member)

    assert_not called
  end

  test "an extension that raises or returns a non-hash is dropped and logged, and the others still apply" do
    Mcp.person_extensions << ->(_subject, _viewer) { raise "boom" }
    Mcp.person_extensions << ->(_subject, _viewer) { "not a hash" }
    Mcp.person_extensions << ->(_subject, _viewer) { { extra: true } }
    logged = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logged)
    result = get(:admin, :ward)
    Rails.logger = original

    assert_nil result.error
    assert_equal true, result.value["extra"]
    assert_equal "Ward World", result.value["name"]
    assert_match(/extension failed.*boom/, logged.string)
  end
end
