require "test_helper"
require_relative "../support/person_fields_world"

# Managers lead the people on their teams, but not admins or architects who
# happen to be members: leader-level field access doesn't reach them.
class PersonFieldsPrivilegedSubjectTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PersonFieldsWorld

  setup do
    host! "localhost"
    build_person_fields_world
    PersonField.ensure_system_fields!
    Membership.create!(person: person(:admin), team: @den_a)
    person(:admin).update!(phone_number: "555-0100")
    @architect = create_world_person("Architect", @den_a)
    @architect.user.update!(architect: true)
    @leaders_only = create_world_field("Leader Notes", read: "leaders", write: "leaders")
    person(:admin).set_field_value(@leaders_only, "admin note")
    @architect.set_field_value(@leaders_only, "architect note")
    person(:a1).set_field_value(@leaders_only, "a1 note")
  end

  test "a team manager can't change an admin's profile details" do
    sign_in person(:den_a_leader).user
    patch person_path(person(:admin)), params: { person: { person_field_values: { phone: "555-6666", address: "Somewhere else" } } }

    assert_equal "555-0100", person(:admin).reload.phone_number
    assert_nil person(:admin).address
  end

  test "a team manager doesn't lead admins or architects in their team" do
    leader = person(:den_a_leader)
    phone = PersonField.system_field("phone_number")

    [ person(:admin), @architect ].each do |subject|
      access = PersonFieldAccess.new(leader, subject)
      assert_not access.component?(:leaders)
      assert_not access.writable?(phone)
      assert_not access.readable?(@leaders_only)
      assert_not_includes phone.writable_subjects_for(leader), subject
      assert_not_includes @leaders_only.readable_subjects_for(leader), subject
    end
  end

  test "a team manager still edits and reads their ordinary members' fields" do
    leader = person(:den_a_leader)
    phone = PersonField.system_field("phone_number")
    assert PersonFieldAccess.new(leader, person(:a1)).writable?(phone)
    assert_includes phone.writable_subjects_for(leader), person(:a1)
    assert_includes @leaders_only.readable_subjects_for(leader), person(:a1)

    sign_in leader.user
    patch person_path(person(:a1)), params: { person: { person_field_values: { phone: "555-7777" } } }
    assert_equal "555-7777", person(:a1).reload.phone_number
  end

  test "admins and architects still edit their own details, and admins anyone's" do
    phone = PersonField.system_field("phone_number")
    assert PersonFieldAccess.new(@architect, @architect).writable?(phone)
    assert PersonFieldAccess.new(person(:admin), @architect).writable?(phone)
    assert_includes @leaders_only.readable_subjects_for(person(:admin)), @architect
  end
end
