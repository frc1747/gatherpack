require "test_helper"
require_relative "../support/person_fields_world"
require_relative "../support/settings_test_helper"

# Birthday decides when a minor guardianship ends, so someone on the child
# side of a guardianship link can't change their own; their guardians and
# leaders still can.
class BirthdaySelfEditTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PersonFieldsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    PersonField.ensure_system_fields!
    @birthday = PersonField.system_field("birthday")
    person(:a1).update!(birthday: Date.current - 12.years)
  end

  test "a minor can't end their guardian's access by changing their birthday" do
    with_settings(guardianship_age_limit: "18") do
      assert_includes person(:parent_a1).wards, person(:a1)

      sign_in person(:a1).user
      patch person_path(person(:a1)), params: { person: { person_field_values: { birthday: "2000-01-01" } } }

      assert_equal Date.current - 12.years, person(:a1).reload.birthday
      assert_includes person(:parent_a1).wards, person(:a1)
    end
  end

  test "the lock holds once the guardianship has lapsed" do
    with_settings(guardianship_age_limit: "18") do
      person(:a1).update!(birthday: Date.current - 20.years)
      assert_not_includes person(:parent_a1).wards, person(:a1)

      assert_not @birthday.writable_by?(person(:a1), person(:a1))
    end
  end

  test "every write check agrees for a ward's own birthday" do
    a1 = person(:a1)

    assert_not @birthday.writable_by?(a1, a1)
    assert_not_includes a1.writable_fields_for(a1), @birthday
    assert_not_includes @birthday.writable_subjects_for(a1), a1
    assert_includes a1.readable_fields_for(a1), @birthday
    assert PersonField.system_field("phone_number").writable_by?(a1, a1)
  end

  test "the profile form shows a ward their birthday read-only" do
    sign_in person(:a1).user
    get edit_person_path(person(:a1))

    assert_response :success
    assert_select "input[name='person[person_field_values][birthday]']", count: 0
    assert_select "##{ActionView::RecordIdentifier.dom_id(@birthday)} .form-text", text: "A team leader can change this for you."
    assert_select "input[name='person[person_field_values][phone]']"

    @birthday.update!(read_permission: "family", write_permission: "family")
    get edit_person_path(person(:a1))
    assert_select "##{ActionView::RecordIdentifier.dom_id(@birthday)} .form-text", text: "Your guardian or a leader can change this for you."
  end

  test "a guardian sets their ward's birthday" do
    @birthday.update!(read_permission: "family", write_permission: "family")
    sign_in person(:parent_a1).user
    patch person_path(person(:a1)), params: { person: { person_field_values: { birthday: "2013-03-04" } } }

    assert_equal Date.new(2013, 3, 4), person(:a1).reload.birthday
  end

  test "a leader sets a ward's birthday" do
    sign_in person(:den_a_leader).user
    patch person_path(person(:a1)), params: { person: { person_field_values: { birthday: "2013-03-04" } } }

    assert_equal Date.new(2013, 3, 4), person(:a1).reload.birthday
  end

  test "someone with no guardian links sets their own birthday" do
    sign_in person(:b1).user
    patch person_path(person(:b1)), params: { person: { person_field_values: { birthday: "1990-02-03" } } }

    assert_equal Date.new(1990, 2, 3), person(:b1).reload.birthday
    assert_includes @birthday.writable_subjects_for(person(:b1)), person(:b1)
  end

  test "a link that grants no guardianship doesn't lock the birthday" do
    Relationship.create!(parent: person(:sibling_a1), child: person(:b1), relationship_type: @sibling_of, created_by: person(:admin))

    assert @birthday.writable_by?(person(:b1), person(:b1))
  end
end
