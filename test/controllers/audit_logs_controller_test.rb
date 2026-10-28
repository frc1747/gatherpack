require "test_helper"

class AuditLogsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @admin = create_user("admin@example.com", admin: true)
    @architect = create_user("architect@example.com", admin: true, architect: true)
  end

  test "an admin who isn't an architect can't roll a hook's code back" do
    hook = as(@architect) { Hook.create!(name: "Greeter", event: "people - create", code: "old_code") }
    as(@architect) { hook.update!(code: "current_code") }

    sign_in @admin
    post revert_audit_log_path(last_version(hook, "update"))

    assert_equal "current_code", hook.reload.code, "a non-architect admin changed a hook's stored code through a revert"
  end

  test "an admin who isn't an architect can't bring back a deleted hook" do
    hook = as(@architect) { Hook.create!(name: "Retired", event: "people - create", code: "removed_on_purpose") }
    as(@architect) { hook.destroy! }

    sign_in @admin
    post revert_audit_log_path(last_version(hook, "destroy"))

    assert_not Hook.exists?(hook.id), "a non-architect admin restored a deleted hook through a revert"
  end

  test "an admin who isn't an architect can't roll a report's code back" do
    report = as(@architect) { Report.create!(name: "Roster", code: "old_report_code") }
    as(@architect) { report.update!(code: "current_report_code") }

    sign_in @admin
    post revert_audit_log_path(last_version(report, "update"))

    assert_equal "current_report_code", report.reload.code, "a non-architect admin changed a report's stored code through a revert"
  end

  test "an admin can't get a removed architect flag back by reverting" do
    as(@architect) { @admin.update!(architect: true) }
    as(@architect) { @admin.update!(architect: false) }

    sign_in @admin
    post revert_audit_log_path(last_version(@admin, "update"))

    assert_not @admin.reload.architect, "an admin regained the architect flag by reverting their own login's version"
  end

  test "an admin who isn't an architect can't revert a gateway's configuration" do
    gateway = as(@architect) { Gateway::StripeGateway.create!(name: "Stripe", secret_key: "sk_test_secret", public_key: "pk_test_x") }
    as(@architect) { gateway.update!(secret: "whsec_webhook") }

    sign_in @admin
    post revert_audit_log_path(last_version(gateway, "update"))

    assert_equal "whsec_webhook", gateway.reload.secret, "a non-architect admin cleared the webhook secret through a revert"
  end

  test "an admin who isn't an architect can't revert a dynamic page" do
    page = as(@architect) { Page.create!(title: "Roster", content: "<%= 1 + 1 %>", dynamic: true, viewer: "admin", editor: "admin") }
    as(@architect) { page.update!(content: "<%= 2 + 2 %>") }

    sign_in @admin
    post revert_audit_log_path(last_version(page, "update"))

    assert_equal "<%= 2 + 2 %>", page.reload.content
  end

  test "an admin who isn't an architect can't make a page dynamic again by reverting" do
    page = as(@architect) { Page.create!(title: "Roster", content: "<%= 1 + 1 %>", dynamic: true, viewer: "admin", editor: "admin") }
    as(@architect) { page.update!(dynamic: false, content: "Plain") }

    sign_in @admin
    post revert_audit_log_path(last_version(page, "update"))

    assert_not page.reload.dynamic
  end

  test "a badge assignment deleted along with its badge can be read but not reverted" do
    assignment = badge_assignments(:one)
    as(@architect) { badges(:one).destroy! }
    version = last_version(assignment, "destroy")

    [ @admin, @architect ].each do |user|
      sign_in user
      get audit_log_path(version)
      assert_response :success
      assert_select "a[href=?]", revert_audit_log_path(version), count: 0

      post revert_audit_log_path(version)
      assert_redirected_to root_path
      assert_not BadgeAssignment.exists?(assignment.id)
    end
  end

  test "an architect can revert a hook's code" do
    hook = as(@architect) { Hook.create!(name: "Greeter", event: "people - create", code: "old_code") }
    as(@architect) { hook.update!(code: "current_code") }

    sign_in @architect
    post revert_audit_log_path(last_version(hook, "update"))

    assert_equal "old_code", hook.reload.code
  end

  test "an admin can revert an ordinary change" do
    team = as(@admin) { Team.create!(name: "Den A", team_type: team_types(:one)) }
    as(@admin) { team.update!(name: "Den B") }
    page = as(@admin) { Page.create!(title: "Notes", content: "Hello", viewer: "team", editor: "admin") }
    as(@admin) { page.update!(content: "Goodbye") }

    sign_in @admin
    post revert_audit_log_path(last_version(team, "update"))
    post revert_audit_log_path(last_version(page, "update"))

    assert_equal "Den A", team.reload.name
    assert_equal "Hello", page.reload.content
  end

  test "the audit entry offers Revert only when the revert is allowed" do
    hook = as(@architect) { Hook.create!(name: "Greeter", event: "people - create", code: "old_code") }
    as(@architect) { hook.update!(code: "current_code") }
    team = as(@admin) { Team.create!(name: "Den A", team_type: team_types(:one)) }
    as(@admin) { team.update!(name: "Den B") }
    hook_version = last_version(hook, "update")
    team_version = last_version(team, "update")

    sign_in @admin
    get audit_log_path(hook_version)
    assert_response :success
    assert_select "a[href=?]", revert_audit_log_path(hook_version), count: 0
    get audit_log_path(team_version)
    assert_select "a[href=?]", revert_audit_log_path(team_version), count: 1

    sign_in @architect
    get audit_log_path(hook_version)
    assert_select "a[href=?]", revert_audit_log_path(hook_version), count: 1
  end

  private

  def create_user(email, **flags)
    user = User.create!(email: email, password: "Password1!", **flags)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    user
  end

  def as(user, &block)
    PaperTrail.request(whodunnit: user.id, &block)
  end

  def last_version(item, event)
    AuditLog.where(item_type: item.class.base_class.name, item_id: item.id, event: event).order(:created_at).last
  end
end
