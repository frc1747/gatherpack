require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::DecideMembershipApplicationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @alpha.update!(join_permission: :requires_approval)
    @application = MembershipApplication.create!(person: person(:guardian), team: @alpha)
  end

  def decide(viewer, decision = "approved", **options)
    call_tool("decide_membership_application", user: user(viewer), membership_application_id: @application.neat_id, decision: decision, **options)
  end

  def assert_unchanged(error)
    assert_refused(error, Membership, AuditLog) { yield }
    assert @application.reload.pending?
  end

  test "an admin approves, which adds the membership, and both are in the call's records" do
    result = nil
    assert_difference("Membership.count", 1) { result = decide(:admin) }

    assert_equal "approved", result.value["status"]
    assert @application.reload.reviewed_at
    membership = Membership.find_by!(person: person(:guardian), team: @alpha)
    assert_equal false, membership.manager
    assert_equal [ @application, membership ], result.changed_records
    assert_equal user(:admin).id.to_s, AuditLog.where(item_type: "MembershipApplication", item_id: @application.id, event: "update").last.whodunnit
  end

  test "a team manager denies, which adds nothing" do
    result = nil
    assert_no_difference("Membership.count") { result = decide(:alpha_manager, "denied") }

    assert_equal "denied", result.value["status"]
    assert @application.reload.denied?
  end

  test "a member on the team can't, and neither can the applicant" do
    assert_unchanged("Not found") { decide(:ward) }

    own = MembershipApplication.create!(person: person(:ward), team: @alpha)
    assert_refused("Not allowed", Membership, AuditLog) { call_tool("decide_membership_application", user: user(:ward), membership_application_id: own.neat_id, decision: "approved") }
    assert_unchanged("Not allowed") { decide(:guardian) }
  end

  test "a member on another team can't reach it" do
    assert_unchanged("Not found") { decide(:beta_member) }
  end

  test "a read token, the setting being off, a bad ID and a bad decision refuse it" do
    assert_unchanged("Not allowed") { decide(:admin, scopes: "mcp_read") }
    assert_unchanged("Writes disabled") { decide(:admin, writes_enabled: false) }
    assert_refused("Not found", Membership) { call_tool("decide_membership_application", user: user(:admin), membership_application_id: @alpha.neat_id, decision: "approved") }
    assert_match(/decision/, decide(:admin, "maybe").error)
    assert @application.reload.pending?
  end

  test "one already decided is refused, as the page offers no action on it" do
    @application.deny!
    assert_refused("This application is already denied", Membership, AuditLog) { decide(:admin) }
  end

  test "what the page would crash on is refused, with nothing changed" do
    Membership.create!(person: person(:guardian), team: @alpha)
    assert_unchanged(/already a member/) { decide(:admin) }

    @alpha.update!(join_permission: :has_account)
    assert_unchanged(/does not require approval/) { decide(:admin, "denied") }
  end

  test "a team that stopped requiring approval refuses either decision, with no audit row or hook" do
    @alpha.update!(join_permission: :has_account)
    Thread.current[:mcp_hook_model] = nil
    Hook.create!(name: "MCP test hook", event: "memberships - create", code: "Thread.current[:mcp_hook_model] = model")

    assert_unchanged(/does not require approval/) { decide(:admin) }
    assert_unchanged(/does not require approval/) { decide(:admin, "denied") }
    assert_nil Thread.current[:mcp_hook_model]
  ensure
    Thread.current[:mcp_hook_model] = nil
  end

  test "a guardian can't decide their ward's application, with the tool or on the page" do
    @application = MembershipApplication.create!(person: person(:ward), team: @alpha)

    assert_unchanged("Not found") { decide(:guardian) }

    sign_in user(:guardian)
    patch team_membership_application_path(@alpha, @application), params: { status: "approved" }
    sign_out user(:guardian)
    assert @application.reload.pending?
  end

  test "it allows and refuses as the page does" do
    [ [ :admin, "approved", :approved ], [ :alpha_manager, "denied", :denied ], [ :ward, "approved", :pending ], [ :beta_member, "denied", :pending ], [ :guardian, "approved", :pending ] ].each do |viewer, decision, expected|
      sign_in user(viewer)
      patch team_membership_application_path(@alpha, @application), params: { status: decision }
      sign_out user(viewer)
      assert_equal expected.to_s, @application.reload.status, "#{viewer} on the page"
      reset_application

      decide(viewer, decision)
      assert_equal expected.to_s, @application.reload.status, "#{viewer} with the tool"
      reset_application
    end
  end

  private

  def reset_application
    Membership.where(person: person(:guardian), team: @alpha).destroy_all
    @application.update!(status: :pending, reviewed_at: nil)
  end
end
