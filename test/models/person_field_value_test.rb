require "test_helper"
require_relative "../support/person_fields_world"
require_relative "../support/settings_test_helper"

class PersonFieldValueTest < ActiveSupport::TestCase
  include PersonFieldsWorld
  include SettingsTestHelper

  setup do
    build_person_fields_world
    @allergies = create_world_field("Food Allergies", read: "family", write: "family")
    @notes = create_world_field("Leader Notes", read: "leaders", write: "leaders")
  end

  test "a guardian can set a field they can write" do
    with_feature do
      a1 = person(:a1)
      a1.assign_field_values({ "food_allergies" => "peanut" }, acting: person(:parent_a1))

      assert a1.save
      assert_equal "peanut", a1.reload.field_value("food_allergies")
      assert_equal person(:parent_a1), a1.person_field_values.first.updated_by
    end
  end

  test "keys the actor can't write are ignored" do
    with_feature do
      a1 = person(:a1)
      a1.assign_field_values({ "food_allergies" => "peanut", "leader_notes" => "sneaky" }, acting: person(:parent_a1))

      assert a1.save
      assert_nil a1.reload.field_value("leader_notes")
    end
  end

  test "a value row rejects a write by someone who can't write the field" do
    row = PersonFieldValue.new(person: person(:a1), person_field: @notes, value: "\"sneaky\"", acting: person(:parent_a1))

    assert_not row.valid?
    assert_includes row.errors[:value], "can't be changed by you"
    row.acting = person(:den_a_leader)
    assert row.valid?
  end

  test "invalid input is reported against the field key" do
    create_world_field("Troop Number", read: "everyone", write: "family", data_type: :integer)

    with_feature do
      a1 = person(:a1)
      a1.assign_field_values({ "troop_number" => "abc" }, acting: person(:a1))

      assert_not a1.save
      assert_includes a1.errors[:troop_number], "must be a whole number"
    end
  end

  test "a required field only binds people who can write it" do
    create_world_field("Emergency Contact", read: "family", write: "leaders", required: true)

    with_feature do
      a1 = person(:a1)
      a1.assign_field_values({ "food_allergies" => "peanut" }, acting: person(:parent_a1))
      assert a1.save

      a1.assign_field_values({}, acting: person(:den_a_leader))
      assert_not a1.valid?
      assert_includes a1.errors[:emergency_contact], "can't be blank"
    end
  end

  test "writing a blank value removes the row" do
    with_feature do
      a1 = person(:a1)
      a1.set_field_value(@allergies, "peanut")

      a1.assign_field_values({ "food_allergies" => " " }, acting: person(:parent_a1))
      assert a1.save

      assert_not PersonFieldValue.exists?(person: a1, person_field: @allergies)
      assert_nil a1.reload.field_value(@allergies)
    end
  end

  test "the value changed hook runs once per changed field, after a successful save" do
    phone = PersonField.create!(name: "Phone", data_type: :phone, system_source: "phone_number", read_permission: "everyone", write_permission: "self_and_leaders")
    create_world_field("Troop Number", read: "everyone", write: "leaders", data_type: :integer)
    Hook.create!(name: "Record", event: "person_fields - value changed",
      code: "(Thread.current[:field_changes] ||= []) << [ model.key, model.old_value, model.new_value, model.changed_by.id ]")
    leader = person(:den_a_leader)
    a1 = person(:a1)
    a1.update!(phone_number: "555-0100")

    with_feature do
      a1.assign_field_values({ "food_allergies" => "peanut", "phone" => "555-0199" }, acting: leader)
      assert a1.save
      assert_equal [
        [ "food_allergies", nil, "peanut", leader.id ],
        [ "phone", "555-0100", "555-0199", leader.id ]
      ], Thread.current[:field_changes].sort_by(&:first)
      assert_equal "555-0199", a1.reload.phone_number

      Thread.current[:field_changes] = []
      a1.assign_field_values({ "food_allergies" => "peanut", "phone" => phone.system_value(a1) }, acting: leader)
      assert a1.save
      assert_empty Thread.current[:field_changes]

      a1.assign_field_values({ "food_allergies" => "shellfish", "troop_number" => "abc" }, acting: leader)
      assert_not a1.save
      assert_empty Thread.current[:field_changes]
      assert_equal "peanut", a1.reload.field_value("food_allergies")
    end
  ensure
    Thread.current[:field_changes] = nil
  end

  test "value rows are hookable" do
    Hook.create!(name: "Record", event: "person_field_values - create", code: "Thread.current[:value_created] = model.person_field.key")

    person(:a1).set_field_value(@allergies, "peanut")

    assert_equal "food_allergies", Thread.current[:value_created]
  ensure
    Thread.current[:value_created] = nil
  end

  test "archiving or re-scoping a field keeps its values" do
    a1 = person(:a1)
    a1.set_field_value(@allergies, "peanut")

    @allergies.archive!
    assert_equal "peanut", a1.field_value(@allergies)
    assert_not_includes a1.readable_fields_for(person(:admin)), @allergies

    @allergies.restore!
    @allergies.update!(team: @den_b)
    assert_not @allergies.applies_to?(a1)
    @allergies.update!(team: nil)
    assert_equal "peanut", a1.reload.field_value(@allergies)
  end

  test "removing a choice keeps the stored value, and the person can keep it" do
    size = create_world_field("Size", read: "everyone", write: "self_and_leaders", data_type: :select, choices: %w[ S M XL ])
    a1 = person(:a1)
    a1.set_field_value(size, "XL")

    size.update!(choices: %w[ S M ])

    assert_equal "XL", a1.field_value(size)
    assert_equal [ "XL", nil ], size.normalize("XL", current: "XL")
    assert_equal [ nil, "isn't one of the choices" ], size.normalize("XL")
  end

  test "email can't be written through person fields" do
    email = PersonField.create!(name: "Email", data_type: :email, system_source: "user.email", read_permission: "everyone", write_permission: "admin")

    assert_not email.writable_by?(person(:admin), person(:a1))
    assert_not email.update(write_permission: "self")

    with_feature do
      a1 = person(:a1)
      a1.assign_field_values({ "email" => "new@example.com" }, acting: person(:admin))
      assert a1.save
      assert_equal "a1@example.com", a1.user.reload.email
    end
  end

  test "readable and writable fields reflect the viewer" do
    with_feature do
      assert_equal [ @allergies ], person(:a1).readable_fields_for(person(:parent_a1))
      assert_equal [ @allergies, @notes ].sort_by(&:name), person(:a1).readable_fields_for(person(:den_a_leader)).sort_by(&:name)
      assert_empty person(:a1).readable_fields_for(person(:a2))
      assert_equal [ @allergies ], person(:a1).writable_fields_for(person(:a1))
    end
  end

  test "custom fields are hidden from profiles and forms while the feature is off" do
    assert_empty person(:a1).readable_fields_for(person(:admin))
  end

  private

  def with_feature(&block)
    with_settings(feature_person_fields: "true", &block)
  end
end
