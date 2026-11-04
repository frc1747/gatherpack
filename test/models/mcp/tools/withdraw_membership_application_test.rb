require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::WithdrawMembershipApplicationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @alpha.update!(join_permission: :requires_approval)
    @application = MembershipApplication.create!(person: person(:guardian), team: @alpha)
  end

  def withdraw(viewer, **options)
    call_tool("withdraw_membership_application", user: user(viewer), membership_application_id: @application.neat_id, **options)
  end

  test "the applicant withdraws their own pending one and gets it back marked removed" do
    result = nil
    assert_difference("MembershipApplication.count", -1) { result = withdraw(:guardian) }

    assert_equal [ @application.neat_id, "pending", true ], result.value.values_at("id", "status", "removed")
    assert_equal user(:guardian).id.to_s, AuditLog.where(item_type: "MembershipApplication", item_id: @application.id, event: "destroy").last.whodunnit
  end

  test "an admin can, even once decided" do
    @application.deny!
    assert_difference("MembershipApplication.count", -1) { assert_nil withdraw(:admin).error }
  end

  test "the applicant can't once it's decided" do
    @application.deny!
    assert_refused("Not allowed", MembershipApplication, AuditLog) { withdraw(:guardian) }
  end

  test "the team's manager sees it but can't withdraw it" do
    assert_refused("Not allowed", MembershipApplication, AuditLog) { withdraw(:alpha_manager) }
  end

  test "a member on the team or another team can't reach it" do
    assert_refused("Not found", MembershipApplication, AuditLog) { withdraw(:ward) }
    assert_refused("Not found", MembershipApplication, AuditLog) { withdraw(:beta_member) }
  end

  test "a read token and the setting being off refuse it" do
    assert_refused("Not allowed", MembershipApplication) { withdraw(:admin, scopes: "mcp_read") }
    assert_refused("Writes disabled", MembershipApplication) { withdraw(:admin, writes_enabled: false) }
  end

  test "it allows and refuses as the page does" do
    %i[admin guardian alpha_manager ward beta_member].each do |viewer|
      page = page_changes_rows?(MembershipApplication, as: user(viewer)) { delete person_membership_application_path(person(:guardian), @application) }
      tool = changes_rows?(MembershipApplication) { withdraw(viewer) }

      assert_equal page, tool, viewer.to_s
    end
  end
end
