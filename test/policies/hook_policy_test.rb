require "test_helper"

class HookPolicyTest < ActiveSupport::TestCase
  def test_scope
    hook = Hook.create!(name: "Sync roster", event: "people - update", code: "model")
    admin = User.new(admin: true)
    member = User.new

    assert HookPolicy::Scope.new(admin, Hook).resolve.exists?(hook.id)
    assert_not HookPolicy::Scope.new(member, Hook).resolve.exists?(hook.id)
    assert_not HookPolicy::Scope.new(nil, Hook).resolve.exists?(hook.id)
  end

  def test_show
  end

  def test_create
  end

  def test_update
  end

  def test_destroy
    admin = User.new(admin: true)
    architect = User.new(admin: true, architect: true)

    assert HookPolicy.new(architect, Hook.new).destroy?
    assert_not HookPolicy.new(admin, Hook.new).destroy?
    assert_not HookPolicy.new(nil, Hook.new).destroy?
  end
end
