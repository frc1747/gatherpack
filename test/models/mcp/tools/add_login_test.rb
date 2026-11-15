require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::AddLoginTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @alpha_new = Person.create!(first_name: "AlphaNew", last_name: "World")
    Membership.create!(person: @alpha_new, team: @alpha)
    @beta_new = Person.create!(first_name: "BetaNew", last_name: "World")
    Membership.create!(person: @beta_new, team: @beta)
  end

  def add_login(viewer, subject, email: "new@example.com", **options)
    call_tool("add_login", user: user(viewer), person_id: subject.neat_id, email: email, **options)
  end

  def assert_no_login(error, subject = @alpha_new)
    before = subject.reload.attributes
    audit_rows = AuditLog.count
    result = assert_refused(error, User) { yield }
    assert_equal before, subject.reload.attributes
    assert_equal audit_rows, AuditLog.count
    assert_empty result.changed_records
    result
  end

  test "an admin creates a login; no password comes back and no mail goes out" do
    result = nil
    assert_no_enqueued_jobs { assert_no_emails { result = add_login(:admin, @beta_new, email: " New@Example.com ") } }

    login = @beta_new.reload.user
    assert_equal "new@example.com", login.email
    assert_equal login, result.changed
    assert_equal [ login, @beta_new ], result.changed_records
    assert_equal true, result.value["has_login"]
    assert_equal call_tool("get_person", user: user(:admin), person_id: @beta_new.neat_id).value, result.value["person"]
    assert_not login.admin?
    assert_not_includes result.value.to_json.downcase, "password"
  end

  test "no password reaches the call log" do
    add_login(:admin, @beta_new)

    call = McpToolCall.where(tool: "add_login").order(:created_at).last
    assert_equal %w[email person_id], call.arguments.keys.sort
    assert_not_includes call.attributes.to_json.downcase, "password"
    assert_not_includes call.attributes.to_json, @beta_new.reload.user.encrypted_password

    assert_no_login(/password/) { add_login(:admin, @alpha_new, password: "client-sent") }
    assert_not_includes McpToolCall.order(:created_at).last.attributes.to_json, "client-sent"
  end

  test "the password is the random token, and differs per login" do
    original = Devise.method(:friendly_token)
    Devise.define_singleton_method(:friendly_token) { |_length = 20| "random-token-for-this-test" }
    begin
      add_login(:admin, @beta_new)
    ensure
      Devise.define_singleton_method(:friendly_token, original)
    end
    assert @beta_new.reload.user.valid_password?("random-token-for-this-test".first(20))

    add_login(:admin, @alpha_new, email: "other@example.com")
    assert_not @alpha_new.reload.user.valid_password?("random-token-for-this-test".first(20))
  end

  test "a failure after the login is saved leaves no login, no link and no audit row" do
    Person.define_method(:update!) { |*| raise ActiveRecord::RecordNotUnique, "lost a race" }
    audit_rows = AuditLog.count
    begin
      assert_equal "Email has already been taken", add_login(:admin, @alpha_new, email: "race@example.com").error
    ensure
      Person.send(:remove_method, :update!)
    end

    assert_not User.exists?(email: "race@example.com")
    assert_nil @alpha_new.reload.user_id
    assert_equal audit_rows, AuditLog.count
  end

  test "an email too long for the index is refused before anything is saved" do
    assert_no_login("Email is too long") { add_login(:admin, @alpha_new, email: "#{"a" * 9_000}@example.com") }
  end

  test "it works for a minor, whose email stays out of the result" do
    @beta_new.update!(birthday: 10.years.ago.to_date)

    result = add_login(:admin, @beta_new)

    assert_equal true, result.value["has_login"]
    assert_not result.value["person"].key?("email")
  end

  test "a team manager can't: PersonPolicy#create? and UserPolicy#create? are for admins" do
    assert_no_login("Not allowed", @alpha_new) { add_login(:alpha_manager, @alpha_new) }
    assert_no_login("Not found", @beta_new) { add_login(:alpha_manager, @beta_new, email: "other@example.com") }
  end

  test "a plain member and a guardian can't" do
    assert_no_login("Not allowed") { add_login(:alpha_member, @alpha_new) }
    assert_no_login("Not found") { add_login(:beta_member, @alpha_new) }
    assert_no_login("Not found") { add_login(:guardian, @alpha_new) }
  end

  test "someone refused doesn't learn whether the person has a login" do
    assert_refused("Not allowed", User) { add_login(:alpha_member, person(:ward)) }
    assert_refused("Not allowed", User) { add_login(:alpha_member, @alpha_new) }
  end

  test "a person with a login, or an email in use, is refused" do
    assert_refused("This person already has a login", User) { add_login(:admin, person(:ward)) }
    assert_equal "ward@example.com", user(:ward).reload.email
    assert_no_login("Email has already been taken") { add_login(:admin, @alpha_new, email: user(:beta_member).email.upcase) }
    assert_no_login("Email is invalid") { add_login(:admin, @alpha_new, email: "not an email") }
    assert_no_login(/Email can't be blank/) { add_login(:admin, @alpha_new, email: "") }
  end

  test "an email on a login with no person is refused, where the page would adopt that login" do
    orphan = User.create!(email: "orphan@example.com", password: "Password1!")
    digest = orphan.encrypted_password

    assert_no_login("Email has already been taken") { add_login(:admin, @alpha_new, email: orphan.email) }
    assert_equal digest, orphan.reload.encrypted_password
    assert_nil orphan.person
  end

  test "bad IDs and types are refused" do
    [ "nonsense", "per_nonsense", @alpha.neat_id ].each do |bad|
      assert_refused("Not found", User) { call_tool("add_login", user: user(:admin), person_id: bad, email: "a@example.com") }
    end
    assert_refused(/email/, User) { call_tool("add_login", user: user(:admin), person_id: @alpha_new.neat_id) }
    assert_refused(/.+/, User) { call_tool("add_login", user: user(:admin), person_id: @alpha_new.neat_id, email: 7) }
  end

  test "a read token and the setting being off refuse it" do
    assert_no_login("Not allowed") { add_login(:admin, @alpha_new, scopes: "mcp_read") }
    assert_no_login("Writes disabled") { add_login(:admin, @alpha_new, writes_enabled: false) }
  end

  test "hooks run, and the audit rows name the token's user" do
    assert_hook_runs("users - create") { add_login(:admin, @alpha_new) }
    login = @alpha_new.reload.user
    assert_equal user(:admin).id, AuditLog.where(item_type: "User", item_id: login.id, event: "create").last.whodunnit
    assert_equal user(:admin).id, AuditLog.where(item_type: "Person", item_id: @alpha_new.id, event: "update").order(:created_at).last.whodunnit
  end

  test "it allows and refuses as the page does" do
    [
      [ :admin, @beta_new, true ],
      [ :alpha_manager, @alpha_new, false ],
      [ :alpha_manager, @beta_new, false ],
      [ :beta_member, @alpha_new, false ],
      [ :guardian, @alpha_new, false ]
    ].each do |viewer, subject, allowed|
      page = page_changes_rows?(User, as: user(viewer)) do
        post person_user_path(subject), params: { user: { email: "page@example.com", password: "Password1!", password_confirmation: "Password1!" } }
      end
      tool = changes_rows?(User) { add_login(viewer, subject) }

      assert_equal allowed, page, "page: #{viewer}"
      assert_equal page, tool, "#{viewer} adding a login for #{subject.first_name}"
    end
  end

  # The policies don't define create? here, so the page's default lets a member in view through.
  test "it refuses a member where the POST goes through on a build with no create?" do
    skip "this build's policy defines create?" if UserPolicy.instance_method(:create?).owner != ApplicationPolicy

    page = page_changes_rows?(User, as: user(:alpha_member)) do
      post person_user_path(@alpha_new), params: { user: { email: "page@example.com", password: "Password1!", password_confirmation: "Password1!" } }
    end
    assert page
    assert_no_login("Not allowed") { add_login(:alpha_member, @alpha_new) }
  end
end
