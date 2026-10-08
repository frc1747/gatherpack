require "test_helper"
require_relative "../support/person_fields_world"
require_relative "../support/settings_test_helper"

class PersonFieldTest < ActiveSupport::TestCase
  include PersonFieldsWorld
  include SettingsTestHelper

  # Who, besides admins, can reach A1's value at each level.
  EXPECTED_FOR_A1 = {
    "admin" => [],
    "self" => %i[ a1 ],
    "leaders" => %i[ den_a_leader pack_leader ],
    "self_and_leaders" => %i[ a1 den_a_leader pack_leader ],
    "guardians" => %i[ parent_a1 den_a_leader pack_leader ],
    "family" => %i[ a1 parent_a1 den_a_leader pack_leader ],
    "team" => %i[ a1 a2 parent_a1 den_a_leader pack_leader assistant ],
    "everyone" => PersonFieldsWorld::PEOPLE - %i[ admin ]
  }.freeze

  setup do
    build_person_fields_world
  end

  test "the read matrix for every level and viewer against A1" do
    EXPECTED_FOR_A1.each do |level, allowed|
      field = create_world_field("Read #{level}", read: level)

      PersonFieldsWorld::PEOPLE.each do |viewer|
        expected = viewer == :admin || allowed.include?(viewer)
        assert_equal expected, field.readable_by?(person(viewer), person(:a1)), "#{viewer} reading a #{level} field"
      end
    end
  end

  test "the write matrix for every level and viewer against A1" do
    EXPECTED_FOR_A1.each do |level, allowed|
      field = create_world_field("Write #{level}", read: "everyone", write: level)

      PersonFieldsWorld::PEOPLE.each do |viewer|
        expected = viewer == :admin || allowed.include?(viewer)
        assert_equal expected, field.writable_by?(person(viewer), person(:a1)), "#{viewer} writing a #{level} field"
      end
    end
  end

  test "team means a shared direct team, not a shared root" do
    field = create_world_field("Shirt", read: "team")

    assert_not field.readable_by?(person(:b1), person(:a1))
    assert_not field.readable_by?(person(:outsider), person(:a1))
    assert field.readable_by?(person(:a2), person(:a1))
  end

  test "a leader of a sub-team isn't responsible for a leader above it" do
    field = create_world_field("Notes", read: "leaders")

    assert_not field.readable_by?(person(:den_a_leader), person(:pack_leader))
    assert field.readable_by?(person(:pack_leader), person(:den_a_leader))
  end

  test "a guardianship runs one way and other relationships grant nothing" do
    field = create_world_field("Allergies", read: "family")

    assert field.readable_by?(person(:parent_a1), person(:a1))
    assert_not field.readable_by?(person(:a1), person(:parent_a1))
    assert_not field.readable_by?(person(:sibling_a1), person(:a1))
    assert_not field.readable_by?(person(:parent_a1), person(:a2))
  end

  test "a team-scoped badge grant reaches that team only" do
    field = create_world_field("Medical", read: "family")
    field.person_field_badge_grants.create!(badge: @assistant_badge, access: :read)

    assert field.readable_by?(person(:assistant), person(:a1))
    assert_not field.readable_by?(person(:assistant), person(:b1))
    assert_not field.writable_by?(person(:assistant), person(:a1))
    assert_equal @assistant_badge, field.access_for(person(:assistant), person(:a1), :read)
  end

  test "an org-wide badge grant reaches everyone, and write implies read" do
    field = create_world_field("Medical", read: "family")
    field.person_field_badge_grants.create!(badge: @health_officer_badge, access: :write)

    %i[ a1 a2 b1 outsider ].each do |subject|
      assert field.readable_by?(person(:health_officer), person(subject)), "reading #{subject}"
      assert field.writable_by?(person(:health_officer), person(subject)), "writing #{subject}"
    end
  end

  test "only admin-assigned badges can grant access" do
    field = create_world_field("Medical", read: "family")
    self_assigned = Badge.create!(name: "Volunteer", short: "Vol", color: "#336699", badge_type: badge_types(:one), team: @den_a, permission: :added_by_manager_or_self)

    grant = field.person_field_badge_grants.build(badge: self_assigned, access: :read)

    assert_not grant.valid?
    assert_includes grant.errors[:badge], "must be one only admins can assign"
  end

  test "who can edit can't reach further than who can see" do
    assert_not PersonField.new(name: "X", read_permission: "leaders", write_permission: "family").valid?
    assert_not PersonField.new(name: "X", read_permission: "team", write_permission: "everyone").valid?
    assert PersonField.new(name: "X", read_permission: "family", write_permission: "self_and_leaders").valid?
    assert PersonField.new(name: "X", read_permission: "everyone", write_permission: "team").valid?
    assert PersonField.new(name: "X", read_permission: "self", write_permission: "admin").valid?
  end

  test "a team-scoped field applies only to people in that team or below" do
    field = create_world_field("Den A only", read: "everyone", team: @den_a)

    assert field.applies_to?(person(:a1))
    assert_not field.applies_to?(person(:pack_leader))
    assert_not field.applies_to?(person(:b1))
    assert_not field.readable_by?(person(:admin), person(:pack_leader))
    assert_equal [ person(:a1), person(:a2), person(:den_a_leader), person(:assistant) ].map(&:id).sort, field.applicable_people.ids.sort
  end

  test "the list form agrees with the per-person check for every viewer" do
    fields = EXPECTED_FOR_A1.keys.map { |level| create_world_field("Level #{level}", read: level, write: level == "everyone" ? "team" : level) }
    granted = create_world_field("Granted", read: "self", write: "self")
    granted.person_field_badge_grants.create!(badge: @assistant_badge, access: :write)
    granted.person_field_badge_grants.create!(badge: @health_officer_badge, access: :read)
    fields << granted
    fields << create_world_field("Den A only", read: "team", write: "family", team: @den_a)

    subjects = Person.all.to_a
    PersonFieldsWorld::PEOPLE.each do |name|
      viewer = person(name)
      accesses = subjects.index_with { |subject| PersonFieldAccess.new(viewer, subject) }

      fields.each do |field|
        expected_read = subjects.select { |subject| accesses[subject].readable?(field) }.map(&:id).sort
        expected_write = subjects.select { |subject| accesses[subject].writable?(field) }.map(&:id).sort

        assert_equal expected_read, field.readable_subjects_for(viewer).ids.sort, "#{name} reading #{field.name}"
        assert_equal expected_write, field.writable_subjects_for(viewer).ids.sort, "#{name} writing #{field.name}"
      end
    end
  end

  test "keys are generated from the name, unique, and fixed after create" do
    first = PersonField.create!(name: "Food Allergies")
    second = PersonField.create!(name: "Food allergies!")
    numbered = PersonField.create!(name: "3rd Contact")
    hyphenated = PersonField.create!(name: "T-Shirt Size (adult)")

    assert_equal "food_allergies", first.key
    assert_equal "food_allergies_2", second.key
    assert_equal "rd_contact", numbered.key
    assert_equal "t_shirt_size_adult", hyphenated.key
    assert_not first.update(key: "allergies")
    assert_includes first.errors[:key], "can't be changed once created"
  end

  test "the type can't change once values exist" do
    field = create_world_field("Notes", read: "everyone")
    person(:a1).set_field_value(field, "hello")

    assert_not field.update(data_type: :text)
  end

  test "select fields need choices without duplicates" do
    field = PersonField.new(name: "Size", data_type: :select)
    assert_not field.valid?
    assert_includes field.errors[:choices], "can't be blank"

    field.choices_text = "S\nM\n\nM\n"
    assert_not field.valid?
    assert_includes field.errors[:choices], "can't contain duplicates"

    field.choices_text = "S\nM\nL"
    assert field.valid?
    assert_equal %w[ S M L ], field.choices
  end

  test "an invalid validation pattern can't be stored" do
    field = PersonField.new(name: "Code", data_type: :string, pattern: "([a-z")

    assert_not field.valid?
    assert field.errors[:pattern].any?
  end

  test "options that don't apply to the type are dropped" do
    field = PersonField.create!(name: "Count", data_type: :integer, min: "1", max: "5", choices: [ "a" ], pattern: "x")

    assert_equal({ "min" => "1", "max" => "5" }, field.options)
  end

  test "inputs are normalized and validated by type" do
    {
      [ :string, {} ] => { " hi " => [ "hi", nil ], "" => [ nil, nil ] },
      [ :string, { pattern: "\\A\\d{3}\\z", pattern_hint: "must be three digits" } ] => { "123" => [ "123", nil ], "12" => [ nil, "must be three digits" ] },
      [ :boolean, {} ] => { "1" => [ true, nil ], "0" => [ nil, nil ] },
      [ :date, { min: "2020-01-01" } ] => { "2021-02-03" => [ Date.new(2021, 2, 3), nil ], "2019-01-01" => [ nil, "must be 2020-01-01 or more" ], "nope" => [ nil, "isn't a valid date" ] },
      [ :integer, { min: "1", max: "10" } ] => { "4" => [ 4, nil ], "11" => [ nil, "must be between 1 and 10" ], "4.5" => [ nil, "must be a whole number" ] },
      [ :select, { choices: %w[ S M ] } ] => { "M" => [ "M", nil ], "XL" => [ nil, "isn't one of the choices" ] },
      [ :phone, {} ] => { "(555) 010-1234" => [ "(555) 010-1234", nil ], "call me" => [ nil, "isn't a valid phone number" ] },
      [ :email, {} ] => { "a@example.com" => [ "a@example.com", nil ], "nope" => [ nil, "isn't a valid email address" ] }
    }.each do |(type, options), cases|
      field = PersonField.new(name: "Field", data_type: type, **options)
      cases.each do |input, expected|
        assert_equal expected, field.normalize(input), "#{type} #{input.inspect}"
      end
    end

    multi = PersonField.new(name: "Allergies", data_type: :multi_select, choices: %w[ peanut shellfish ])
    assert_equal [ %w[ peanut shellfish ], nil ], multi.normalize([ "", "peanut", "shellfish" ])
    assert_equal [ nil, nil ], multi.normalize([ "" ])
    assert_equal [ nil, "includes a choice that isn't available" ], multi.normalize([ "gluten" ])
  end

  test "values round-trip through storage" do
    {
      string: "hello", text: "line one\nline two", boolean: true, date: Date.new(2026, 1, 2),
      integer: 42, multi_select: %w[ peanut shellfish ], phone: "555-0100", email: "a@example.com"
    }.each do |type, value|
      field = PersonField.new(data_type: type)
      assert_equal value, field.cast(field.serialize(value)), type.to_s
    end
    assert_equal false, PersonField.new(data_type: :boolean).cast(nil)
    assert_nil PersonField.new(data_type: :string).cast(nil)
  end

  test "fields are ordered by section, then position, then name" do
    later = PersonFieldGroup.create!(name: "Later", position: 2)
    earlier = PersonFieldGroup.create!(name: "Earlier", position: 1)
    create_world_field("Zed", read: "everyone", person_field_group: later)
    create_world_field("Beta", read: "everyone", person_field_group: earlier, position: 1)
    create_world_field("Alpha", read: "everyone", person_field_group: earlier, position: 1)
    create_world_field("First", read: "everyone", person_field_group: earlier, position: 0)
    create_world_field("Ungrouped", read: "everyone")

    assert_equal %w[ Ungrouped First Alpha Beta Zed ], PersonField.ordered.map(&:name)
  end

  test "custom fields are only in use while the feature is on" do
    field = create_world_field("Notes", read: "everyone")

    with_settings(feature_person_fields: "false") { assert_not_includes PersonField.in_use, field }
    with_settings(feature_person_fields: "true") { assert_includes PersonField.in_use, field }
  end

  test "a field must be archived, and not a system field, before it can be destroyed" do
    field = create_world_field("Notes", read: "everyone")
    person(:a1).set_field_value(field, "hello")

    assert_not field.destroy
    assert PersonFieldValue.exists?(person_field: field)

    field.archive!
    assert field.destroy
    assert_not PersonFieldValue.exists?(person_field_id: field.id)

    system = PersonField.create!(name: "Phone", data_type: :phone, system_source: "phone_number", read_permission: "everyone", write_permission: "self_and_leaders")
    system.archive!
    assert_not system.destroy
  end

  test "definition changes are hookable" do
    expected = %w[ person_fields person_field_values person_field_badge_grants ].flat_map do |table|
      %w[ create update destroy ].map { |action| "#{table} - #{action}" }
    end

    assert_empty expected + [ "person_fields - value changed" ] - Hook.catalog
  end
end
