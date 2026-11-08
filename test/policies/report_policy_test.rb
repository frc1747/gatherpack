require "test_helper"

class ReportPolicyTest < ActiveSupport::TestCase
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

    assert ReportPolicy.new(architect, Report.new).destroy?
    assert_not ReportPolicy.new(admin, Report.new).destroy?
    assert_not ReportPolicy.new(nil, Report.new).destroy?
  end
end
