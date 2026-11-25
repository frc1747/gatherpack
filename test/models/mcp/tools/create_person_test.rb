require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::CreatePersonTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
  end

  def create_person(viewer, **options)
    call_tool("create_person", user: user(viewer), first_name: "New", last_name: "Comer", **options)
  end

  # Nothing changed: no rows, no audit rows.
  def assert_nothing_created(error)
    audit_rows = AuditLog.count
    result = assert_refused(error, Person, User, Membership) { yield }
    assert_equal audit_rows, AuditLog.count
    result
  end

  GENERATED_PASSWORD = "secret-generated-password-value".first(20)

  def with_generated_password
    original = Devise.method(:friendly_token)
    Devise.define_singleton_method(:friendly_token) { |_length = 20| "secret-generated-password-value" }
    yield
  ensure
    Devise.define_singleton_method(:friendly_token, original)
  end

  test "an admin creates a person with no team, and gets them back as get_person shows them" do
    result = create_person(:admin, display_name: "Newcomer")

    person = Person.find_by!(first_name: "New", last_name: "Comer")
    assert_equal person, result.changed
    assert_equal [ person ], result.changed_records
    assert_equal person.neat_id, result.value["id"]
    assert_equal "Newcomer", result.value["name"]
    assert_equal false, result.value["has_login"]
    assert_nil person.user
    assert_equal call_tool("get_person", user: user(:admin), person_id: person.neat_id).value, result.value.except("has_login")
  end

  test "the display name defaults as on the page, and a blank email makes no login" do
    [ "", "   " ].each do |blank|
      result = create_person(:admin, email: blank)
      assert_equal "New Comer", result.value["name"]
      assert_equal false, result.value["has_login"]
    end
  end

  test "with an email it creates the login; no mail goes out and no password comes back" do
    result = nil
    assert_no_enqueued_jobs { assert_no_emails { result = create_person(:admin, email: "  New.Comer@example.com ") } }

    person = Person.find_by!(first_name: "New")
    assert_equal "new.comer@example.com", person.user.email
    assert person.user.encrypted_password.present?
    assert_equal true, result.value["has_login"]
    assert_equal [ person, person.user ], result.changed_records
    assert_not_includes result.value.to_json.downcase, "password"
    # No birthday on file: withheld whoever is asking.
    assert_not result.value.key?("email")
  end

  test "no password reaches the call log or the audit log, even when a client sends one" do
    with_generated_password do
      result = call_tool("create_person", user: user(:admin), first_name: "New", last_name: "Comer", email: "new@example.com")
      assert_not result.error?
    end

    call = McpToolCall.where(tool: "create_person").order(:created_at).last
    assert_equal({ "first_name" => "New", "last_name" => "Comer", "email" => "new@example.com" }, call.arguments)
    assert_not_includes call.attributes.to_json, GENERATED_PASSWORD
    user = User.find_by!(email: "new@example.com")
    assert_not_includes AuditLog.where(item_type: "User", item_id: user.id).map(&:attributes).to_json, GENERATED_PASSWORD
    assert user.valid_password?(GENERATED_PASSWORD), "the password is the random token, not the page's word pair"

    assert_nothing_created(/password/) { call_tool("create_person", user: user(:admin), first_name: "A", last_name: "B", password: "client-sent") }
    assert_not_includes McpToolCall.order(:created_at).last.attributes.to_json, "client-sent"
  end

  test "an email in use, or an invalid one, refuses the whole call" do
    assert_nothing_created(/Email has already been taken/) { create_person(:admin, email: user(:ward).email.upcase) }
    assert_nothing_created(/Email is invalid/) { create_person(:admin, email: "not an email", team_id: @alpha.neat_id) }

    orphan = User.create!(email: "orphan@example.com", password: "Password1!")
    assert_nothing_created(/Email has already been taken/) { create_person(:admin, email: orphan.email) }
  end

  test "an email too long for the index is refused before anything is saved" do
    assert_nothing_created("Email is too long") { create_person(:admin, email: "#{"a" * 9_000}@example.com") }
    assert_not_includes McpToolCall.order(:created_at).last.error_message, "aaa"
  end

  test "a hook on the new person sees the email, as from the page" do
    Thread.current[:mcp_hook_email] = nil
    Hook.create!(name: "MCP test hook", event: "people - create", code: "Thread.current[:mcp_hook_email] = model.email")

    sign_in user(:admin)
    post people_path, params: { person: { first_name: "Page", last_name: "Made", email: "hook-page@example.com" } }
    sign_out user(:admin)
    assert_equal "hook-page@example.com", Thread.current[:mcp_hook_email]

    create_person(:admin, email: "hook-tool@example.com")
    assert_equal "hook-tool@example.com", Thread.current[:mcp_hook_email]
  ensure
    Thread.current[:mcp_hook_email] = nil
  end

  test "a failure after the first save leaves nothing behind, and hook-free checks come first" do
    Thread.current[:mcp_hook_model] = nil
    Hook.create!(name: "MCP test hook", event: "people - create", code: "Thread.current[:mcp_hook_model] = model")
    assert_nothing_created(/already been taken/) { create_person(:admin, email: user(:ward).email) }
    assert_nil Thread.current[:mcp_hook_model], "a refusal found up front doesn't fire hooks"

    Membership.define_method(:save!) { |**| raise ActiveRecord::RecordNotUnique, "lost a race" }
    begin
      assert_equal "Email has already been taken", create_person(:admin, email: "race@example.com", team_id: @alpha.neat_id).error
    ensure
      Membership.send(:remove_method, :save!)
    end
    assert_not Person.exists?(first_name: "New"), "the person rolled back"
    assert_not User.exists?(email: "race@example.com"), "the login rolled back"
    assert_not AuditLog.where(item_type: "Person").where("object_changes::text LIKE ?", "%Comer%").exists?, "the audit rows rolled back"
  ensure
    Thread.current[:mcp_hook_model] = nil
  end

  test "with a team it adds the membership, and manager needs a team" do
    result = create_person(:admin, team_id: @beta.neat_id, manager: true, email: "new@example.com")

    person = Person.find_by!(first_name: "New")
    membership = person.memberships.first
    assert_equal @beta, membership.team
    assert_predicate membership, :manager?
    assert_equal [ person, person.user, membership ], result.changed_records
    assert_equal [ true ], result.value["teams"].map { |team| team["manager"] }

    assert_nothing_created("manager needs team_id") { create_person(:admin, manager: true) }
    assert_not_nil create_person(:admin, manager: false).value
  end

  test "a team manager can't, on any team: PersonPolicy#create? is for admins, and comes before the team lookup" do
    assert_nothing_created("Not allowed") { create_person(:alpha_manager, team_id: @alpha.neat_id, manager: true) }
    assert_nothing_created("Not allowed") { create_person(:alpha_manager) }
    assert_nothing_created("Not allowed") { create_person(:alpha_manager, team_id: @beta.neat_id) }
    assert_not page_changes_rows?(Person, as: user(:alpha_manager)) { post people_path, params: { person: { first_name: "A", last_name: "B" } } }
  end

  test "a manager of a parent team can't create on a sub-team either" do
    kid = create_world_team("Kid", parent: @alpha)

    assert_nothing_created("Not allowed") { create_person(:alpha_manager, team_id: kid.neat_id) }
  end

  test "a plain member and a guardian can't, even on a team open to any account" do
    @beta.update!(join_permission: :has_account)

    assert_nothing_created("Not allowed") { create_person(:beta_member) }
    assert_nothing_created("Not allowed") { create_person(:beta_member, team_id: @beta.neat_id) }
    assert_nothing_created("Not allowed") { create_person(:beta_member, team_id: @alpha.neat_id) }
    assert_nothing_created("Not allowed") { create_person(:guardian) }
    assert_nothing_created("Not allowed") { create_person(:guardian, team_id: @alpha.neat_id) }
  end

  test "bad IDs and types are refused" do
    [ "nonsense", "tm_nonsense", "", @access_badge.neat_id ].each do |bad|
      assert_nothing_created("Not found") { create_person(:admin, team_id: bad) }
    end
    assert_nothing_created(/.+/) { create_person(:admin, manager: "no", team_id: @alpha.neat_id) }
    assert_nothing_created(/.+/) { call_tool("create_person", user: user(:admin), first_name: 7, last_name: "B") }
    assert_nothing_created(/last_name/) { call_tool("create_person", user: user(:admin), first_name: "A") }
    assert_nothing_created(/control characters/) { call_tool("create_person", user: user(:admin), first_name: "A\nB", last_name: "C") }
  end

  test "what it doesn't take is refused by name, not dropped" do
    assert_nothing_created(/phone_number/) { create_person(:admin, phone_number: "555-0100") }
    assert_not_includes McpToolCall.order(:created_at).last.attributes.to_json, "555-0100"
  end

  test "a read token and the setting being off refuse it" do
    assert_nothing_created("Not allowed") { create_person(:admin, scopes: "mcp_read") }
    assert_nothing_created("Writes disabled") { create_person(:admin, writes_enabled: false) }
  end

  test "hooks run, and the audit row names the token's user" do
    assert_hook_runs("people - create") { create_person(:admin) }
    person = Person.where(first_name: "New").order(:created_at).last
    assert_equal user(:admin).id, AuditLog.where(item_type: "Person", item_id: person.id, event: "create").last.whodunnit
    assert_hook_runs("users - create") do
      result = create_person(:admin, email: "hooked@example.com")
      Mcp::Tool::Result.new(outcome: :ok, value: result.value, changed: result.changed_records.last)
    end
  end

  test "it creates with the same values as the page" do
    sign_in user(:admin)
    post people_path, params: { person: { first_name: "Page", last_name: "Made", email: "page@example.com" } }
    sign_out user(:admin)
    call_tool("create_person", user: user(:admin), first_name: "Page", last_name: "Made", email: "tool@example.com")

    page, tool = %w[page@example.com tool@example.com].map { |email| Person.find_by!(user: User.find_by!(email: email)) }
    %i[first_name last_name display_name].each { |attribute| assert_equal page[attribute], tool[attribute] }
    assert_not page.user.admin?
    assert_not tool.user.admin?
  end

  test "on a build whose policy defines create?, it allows and refuses as the page does" do
    with_policy_query(PersonPolicy, :create?, proc { user.admin? }) do
      [ [ :admin, true ], [ :alpha_manager, false ], [ :beta_member, false ] ].each do |viewer, allowed|
        options = viewer == :admin ? {} : { team_id: @alpha.neat_id }
        page = page_changes_rows?(Person, as: user(viewer)) { post people_path, params: { person: { first_name: "A", last_name: "B" } } }
        tool = changes_rows?(Person) { create_person(viewer, **options) }

        assert_equal allowed, page, viewer
        assert_equal page, tool, viewer
      end
    end
  end

  # PersonPolicy defines no create? here, so the page's default lets anyone through.
  # That default isn't a rule a tool may rely on (Mcp::Context).
  test "it refuses a member where the POST goes through on a build with no create?" do
    skip "this build's policy defines create?" if PersonPolicy.instance_method(:create?).owner != ApplicationPolicy

    assert page_changes_rows?(Person, as: user(:beta_member)) { post people_path, params: { person: { first_name: "A", last_name: "B" } } }
    assert_nothing_created("Not allowed") { create_person(:beta_member) }
  end
end
