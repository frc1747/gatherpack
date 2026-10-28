require "test_helper"

class PersonPolicyTest < ActiveSupport::TestCase
  def test_scope
  end

  def test_show
  end

  def test_create
    admin = create_person("admin@example.com", admin: true)
    member = create_person("member@example.com")
    manager = create_person("manager@example.com")
    Membership.create!(person: manager, team: teams(:one), manager: true)

    assert PersonPolicy.new(admin.user, Person.new).create?
    assert PersonPolicy.new(admin.user, Person).new?
    assert_not PersonPolicy.new(member.user, Person.new).create?
    assert_not PersonPolicy.new(member.user, Person).new?
    assert_not PersonPolicy.new(manager.user, Person.new).create?
  end

  def test_update
  end

  def test_impersonate
    admin = create_person("admin@example.com", admin: true)
    architect = create_person("architect@example.com", admin: true, architect: true)
    other_architect = create_person("other-architect@example.com", admin: true, architect: true)
    member = create_person("member@example.com")

    assert PersonPolicy.new(admin.user, member).impersonate?
    assert_not PersonPolicy.new(admin.user, architect).impersonate?
    assert PersonPolicy.new(architect.user, other_architect).impersonate?
    assert PersonPolicy.new(architect.user, member).impersonate?
    assert_not PersonPolicy.new(member.user, admin).impersonate?
  end

  def test_destroy
  end

  private

  def create_person(email, admin: false, architect: false)
    user = User.create!(email: email, password: "Password1!", admin: admin, architect: architect)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
  end
end
