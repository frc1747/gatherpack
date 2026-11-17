require "test_helper"
require_relative "../../support/mcp_world"

class Mcp::CallsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    call_tool("whoami", user: user(:alpha_member))
    call_tool("search_people", user: user(:beta_member), query: "secretname")
  end

  test "an admin sees the log, newest first" do
    sign_in user(:admin)
    get mcp_calls_path

    assert_response :success
    assert_select "h1", "MCP Calls"
    assert_select "tbody tr", 2
    assert_select "tbody tr:first-child tt", "search_people"
    assert_includes response.body, "secretname"
    # code_editor.js empties a code element with no pre inside it.
    assert_select "tbody code", false
  end

  test "a call shows how many records it changed and links those with a page" do
    membership = Membership.find_by!(person: person(:ward), team: @alpha)
    McpToolCall.create!(user: user(:admin), tool: "several", outcome: "ok", changed_records: [
      { type: "Person", id: person(:ward).id }, { type: "Team", id: @alpha.id }, { type: "Membership", id: membership.id }
    ])
    sign_in user(:admin)
    get mcp_calls_path

    assert_select "tbody tr:first-child summary", "3 records"
    assert_select "tbody tr:first-child a[href=?]", person_path(person(:ward).id), "Person #{person(:ward).display_name}"
    assert_select "tbody tr:first-child a[href=?]", team_path(@alpha.id)
    assert_select "tbody tr:first-child a", 3
    assert_select "tbody tr:first-child a[href=?]", team_membership_path(@alpha.id, membership.id), "Membership #{membership.id}"

    get person_path(person(:ward).id)
    assert_response :success
    get team_membership_path(@alpha.id, membership.id)
    assert_response :success
  end

  test "a person is named as they are now, not by ID" do
    ward = person(:ward)
    McpToolCall.create!(user: user(:admin), tool: "update_person", outcome: "ok", changed_records: [ { type: "Person", id: ward.id } ])
    sign_in user(:admin)
    get mcp_calls_path
    assert_select "tbody tr:first-child a[href=?]", person_path(ward.id), "Person #{ward.display_name}"

    ward.update_columns(display_name: "Renamed Ward")
    get mcp_calls_path
    assert_select "tbody tr:first-child a[href=?]", person_path(ward.id), "Person Renamed Ward"
    assert_not_includes css_select("tbody tr:first-child").text, ward.id
  end

  test "a person who no longer exists shows as text with a note" do
    gone = Person.create!(first_name: "Gone", last_name: "Person")
    gone_id = gone.id
    gone.destroy!
    McpToolCall.create!(user: user(:admin), tool: "update_person", outcome: "ok", changed_records: [ { type: "Person", id: gone_id } ])
    sign_in user(:admin)
    get mcp_calls_path

    assert_select "tbody tr:first-child a", 0
    assert_includes css_select("tbody tr:first-child").text, "Person #{gone_id} (no longer exists)"
  end

  test "names for a whole page come from one query per type" do
    3.times { McpToolCall.create!(user: user(:admin), tool: "several", outcome: "ok", changed_records: [ { type: "Person", id: person(:ward).id }, { type: "Team", id: @alpha.id } ]) }
    sign_in user(:admin)
    queries = []
    counter = ->(*, payload) { queries << payload[:sql] if payload[:sql].match?(/SELECT "(people|teams)"."id", "(people|teams)"."(display_name|name)" FROM/) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get mcp_calls_path }

    assert_equal 2, queries.size, queries.join("\n")
    assert_select "tbody tr:first-child a[href=?]", team_path(@alpha.id), "Team #{@alpha.name}"
  end

  test "a membership that has since been removed shows as text, and a login isn't linked" do
    gone = Membership.create!(person: person(:beta_member), team: @alpha)
    gone_id = gone.id
    gone.destroy!
    McpToolCall.create!(user: user(:admin), tool: "several", outcome: "ok", changed_records: [
      { type: "Membership", id: gone_id }, { type: "User", id: user(:ward).id }
    ])
    sign_in user(:admin)
    get mcp_calls_path

    assert_response :success
    assert_select "tbody tr:first-child a", 0
    assert_includes css_select("tbody tr:first-child").text, "Membership #{gone_id}"
    assert_includes css_select("tbody tr:first-child").text, "User #{user(:ward).id}"
  end

  test "a changed token links to its page" do
    token = Token.create!(tokenable: person(:ward), value: "170000000034")
    McpToolCall.create!(user: user(:admin), tool: "add_token", outcome: "ok", changed_type: "Token", changed_id: token.id, changed_records: [ { type: "Token", id: token.id } ])
    sign_in user(:admin)
    get mcp_calls_path

    assert_select "tbody tr:first-child a[href=?]", token_path(token.id), "Token #{token.id}"
    assert_not_includes response.body, "170000000034"
  end

  test "a removed token shows as text, not a link to a page that's gone" do
    token = Token.create!(tokenable: person(:ward), value: "170000000034")
    token_id = token.id
    with_settings(mcp_write_enabled: "true") { assert_nil Mcp.tool("remove_token").run(mcp_context(user(:admin), scopes: "mcp_write"), { token_id: token.neat_id }).error }
    sign_in user(:admin)
    get mcp_calls_path

    assert_select "tbody tr:first-child a[href=?]", token_path(token_id), false
    assert_includes css_select("tbody tr:first-child").text, "Token #{token_id}"
  end

  test "a single change links too, and a call from before changed_records still shows" do
    McpToolCall.create!(user: user(:admin), tool: "older", outcome: "ok", changed_type: "Person", changed_id: person(:ward).id)
    sign_in user(:admin)
    get mcp_calls_path

    assert_select "tbody tr:first-child", /1 record/
    assert_select "tbody tr:first-child a[href=?]", person_path(person(:ward).id)
    assert_select "tbody tr:nth-child(2) a", 0
  end

  test "a call with unexpected failures shows its note, though its outcome is ok" do
    McpToolCall.create!(user: user(:admin), tool: "bulk", outcome: "ok", error_message: "2 records failed unexpectedly")
    sign_in user(:admin)
    get mcp_calls_path

    assert_select "tbody tr:first-child small", "2 records failed unexpectedly"
  end

  test "a real create_person call shows its records" do
    call_tool("create_person", user: user(:admin), first_name: "New", last_name: "Comer", email: "new@example.com", team_id: @alpha.neat_id)
    created = Person.find_by!(first_name: "New")
    sign_in user(:admin)
    get mcp_calls_path

    assert_select "tbody tr:first-child summary", "3 records"
    assert_select "tbody tr:first-child a[href=?]", person_path(created.id)
    assert_not_includes response.body.downcase, "password"
  end

  test "an admin filters by user and tool" do
    sign_in user(:admin)

    get mcp_calls_path, params: { q: { user_id_eq: user(:alpha_member).id } }
    assert_select "tbody tr", 1
    assert_select "tbody tr tt", "whoami"

    get mcp_calls_path, params: { q: { tool_eq: "search_people" } }
    assert_select "tbody tr", 1
    assert_select "tbody tr tt", "search_people"
  end

  test "a member is refused" do
    sign_in user(:alpha_member)
    get mcp_calls_path

    assert_redirected_to root_path
    assert_equal "You are not allowed to do that", flash[:notice]
  end

  test "signed out goes to sign-in" do
    get mcp_calls_path

    assert_redirected_to new_user_session_path
  end

  test "feature off is a 404" do
    sign_in user(:admin)
    with_feature(:mcp, false) do
      get mcp_calls_path
      assert_response :not_found
    end
  end

  test "signed out with the feature off is a 404 too" do
    with_feature(:mcp, false) do
      get mcp_calls_path
      assert_response :not_found
    end
    with_feature(:oauth_provider, false) do
      get mcp_calls_path
      assert_response :not_found
    end
  end

  test "admins reach it from the sidebar, right after the audit log" do
    sign_in user(:admin)
    get setup_path

    links = css_select(".sidebar a").pluck("href")
    assert_equal links.index(audit_logs_path) + 1, links.index(mcp_calls_path)
    assert_select "a[href=?]", mcp_calls_path, 1, "only the sidebar links to it, not the setup page"
  end

  test "members don't get the sidebar link" do
    sign_in user(:alpha_member)
    get root_path

    assert_select "a[href=?]", mcp_calls_path, 0
  end

  test "the sidebar link goes away when the feature is off" do
    sign_in user(:admin)
    with_feature(:mcp, false) do
      get setup_path

      assert_select "a[href=?]", mcp_calls_path, 0
    end
  end
end
