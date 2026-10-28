require "test_helper"

class HookPolicyTest < ActiveSupport::TestCase
  def test_scope
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
