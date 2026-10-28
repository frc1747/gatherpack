require "test_helper"

class AuditLogPolicyTest < ActiveSupport::TestCase
  def test_scope
    admin = create_user("admin@example.com", admin: true)
    architect = create_user("architect@example.com", admin: true, architect: true)
    gateway = Gateway::StripeGateway.create!(name: "Stripe", secret_key: "sk_test_secret", public_key: "pk_test_x")
    team = Team.create!(name: "Den A", team_type: team_types(:one))

    visible = AuditLogPolicy::Scope.new(admin, AuditLog).resolve
    assert_not visible.exists?(item_id: gateway.id)
    assert visible.exists?(item_id: team.id)
    assert AuditLogPolicy::Scope.new(architect, AuditLog).resolve.exists?(item_id: gateway.id)
  end

  def test_show
    admin = create_user("admin@example.com", admin: true)
    architect = create_user("architect@example.com", admin: true, architect: true)
    gateway = Gateway::StripeGateway.create!(name: "Stripe", secret_key: "sk_test_secret", public_key: "pk_test_x")
    team = Team.create!(name: "Den A", team_type: team_types(:one))

    assert_not AuditLogPolicy.new(admin, gateway.versions.last).show?
    assert AuditLogPolicy.new(architect, gateway.versions.last).show?
    assert AuditLogPolicy.new(admin, team.versions.last).show?
  end

  # Every versioned model whose policy is architect-only has to be listed, or
  # its entries show its attributes to admins who aren't architects.
  def test_architect_only_item_types
    Rails.application.eager_load!
    versioned = ApplicationRecord.descendants.select { |model| model.try(:paper_trail_options) }.map(&:base_class).uniq
    architect_only = versioned.select do |model|
      policy = Pundit::PolicyFinder.new(model).policy
      policy && policy <= ArchitectPolicy
    end

    assert_equal AuditLogPolicy::ARCHITECT_ONLY_ITEM_TYPES.sort, architect_only.map(&:name).sort
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
