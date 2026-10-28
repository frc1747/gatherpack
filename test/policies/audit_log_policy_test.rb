require "test_helper"

class AuditLogPolicyTest < ActiveSupport::TestCase
  def test_scope
  end

  def test_show
  end

  def test_create
  end

  def test_update
  end

  def test_destroy
  end

  def test_revert
    admin = create_user("admin@example.com", admin: true)
    architect = create_user("architect@example.com", admin: true, architect: true)
    member = create_user("member@example.com")
    hook = Hook.create!(name: "Greeter", event: "people - create", code: "old_code")
    hook.update!(code: "current_code")
    team = Team.create!(name: "Den A", team_type: team_types(:one))
    team.update!(name: "Den B")
    hook_version = hook.versions.where(event: "update").last
    team_version = team.versions.where(event: "update").last

    assert AuditLogPolicy.new(architect, hook_version).revert?
    assert_not AuditLogPolicy.new(admin, hook_version).revert?
    assert AuditLogPolicy.new(admin, team_version).revert?
    assert_not AuditLogPolicy.new(member, team_version).revert?
  end

  private

  def create_user(email, **flags)
    user = User.create!(email: email, password: "Password1!", **flags)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    user
  end
end
