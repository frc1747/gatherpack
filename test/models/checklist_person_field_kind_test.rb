require "test_helper"
require_relative "../support/checklists_world"

class ChecklistPersonFieldKindTest < ActiveSupport::TestCase
  include ChecklistsWorld

  setup do
    build_checklists_world
    @checklist = create_world_checklist
  end

  def with_fields(&block)
    with_settings(feature_person_fields: "true", feature_checklists: "true", &block)
  end

  def create_field(name, data_type, **attributes)
    PersonField.create!({ name: name, data_type: data_type, read_permission: "admin", write_permission: "admin" }.merge(attributes))
  end

  def add_field_item(field, operator, config = {})
    add_item(@checklist, :person_field, field.name, { field_id: field.id, operator: operator }.merge(config))
  end

  def assign(name, field, value)
    person(name).set_field_value(field, value)
  end

  test "text and choice fields: is any of and is none of, ignoring case" do
    with_fields do
      size = create_field("Size", :select, choices: %w[ S M L ])
      assign(:member, size, "M")
      assign(:member2, size, "S")
      any = add_field_item(size, "any_of", values: "m, L")
      none = add_field_item(size, "none_of", values: "m, L")

      assert_equal "met", evaluate(@checklist, :member, any).status
      assert_equal "not_met", evaluate(@checklist, :member2, any).status
      assert_equal "not_met", evaluate(@checklist, :member, none).status
      assert_equal "met", evaluate(@checklist, :member2, none).status
    end
  end

  test "multi select: any of the chosen values" do
    with_fields do
      skills = create_field("Skills", :multi_select, choices: %w[ Cook Drive Sew ])
      assign(:member, skills, %w[ Cook Sew ])
      assign(:member2, skills, %w[ Drive ])
      item = add_field_item(skills, "any_of", values: "Sew")

      assert_equal "met", evaluate(@checklist, :member, item).status
      assert_equal "not_met", evaluate(@checklist, :member2, item).status
    end
  end

  test "yes and no fields" do
    with_fields do
      permission = create_field("Permission slip", :boolean)
      assign(:member, permission, true)
      assign(:member2, permission, false)
      yes = add_field_item(permission, "yes")
      no = add_field_item(permission, "no")

      assert_equal "met", evaluate(@checklist, :member, yes).status
      assert_equal "not_met", evaluate(@checklist, :member2, yes).status
      assert_equal "met", evaluate(@checklist, :member2, no).status
      assert_equal "not_met", evaluate(@checklist, :member, no).status
    end
  end

  test "date fields: on or after and on or before" do
    with_fields do
      physical = create_field("Physical date", :date)
      assign(:member, physical, Date.new(2026, 9, 15))
      assign(:member2, physical, Date.new(2025, 9, 15))
      after = add_field_item(physical, "on_or_after", date: "2026-09-01")
      before = add_field_item(physical, "on_or_before", date: "2025-12-31")

      assert_equal "met", evaluate(@checklist, :member, after).status
      assert_equal "not_met", evaluate(@checklist, :member2, after).status
      assert_equal "met", evaluate(@checklist, :member2, before).status
      assert_equal "not_met", evaluate(@checklist, :member, before).status
    end
  end

  test "number fields: at least and at most" do
    with_fields do
      hours = create_field("Hours", :integer)
      assign(:member, hours, 10)
      assign(:member2, hours, 3)
      least = add_field_item(hours, "at_least", number: 5)
      most = add_field_item(hours, "at_most", number: 5)

      assert_equal "met", evaluate(@checklist, :member, least).status
      assert_equal "not_met", evaluate(@checklist, :member2, least).status
      assert_equal "met", evaluate(@checklist, :member2, most).status
      assert_equal "not_met", evaluate(@checklist, :member, most).status
    end
  end

  test "built-in fields read the profile column" do
    with_fields do
      PersonField.ensure_system_fields!
      birthday = PersonField.system_field("birthday")
      item = add_field_item(birthday, "on_or_before", date: "2015-01-01")

      assert_equal "met", evaluate(@checklist, :kid, item).status
      assert_equal "not_met", evaluate(@checklist, :member, item).status, "no birthday"
    end
  end

  test "missing data is not yet unless the item says blank counts as met" do
    with_fields do
      note = create_field("Note", :string)
      filled = add_field_item(note, "filled_in")
      none = add_field_item(note, "none_of", values: "x")
      lenient = add_field_item(note, "none_of", values: "x", blank: "met")
      lenient_filled = add_field_item(note, "filled_in", blank: "met")

      result = evaluate(@checklist, :member, filled)
      assert_equal "not_met", result.status
      assert_equal "Update note", result.fix["label"]
      assert_equal "not_met", evaluate(@checklist, :member, none).status
      assert_equal "met", evaluate(@checklist, :member, lenient).status
      assert_equal "not_met", evaluate(@checklist, :member, lenient_filled).status, "blank is never filled in"

      assign(:member, note, "hello")
      assert_equal "met", evaluate(@checklist, :member, filled).status
    end
  end

  test "results never carry the value" do
    with_fields do
      note = create_field("Allergies", :string)
      assign(:member, note, "peanuts")
      none = add_field_item(note, "none_of", values: "gluten")
      other = add_field_item(note, "any_of", values: "gluten")

      [ none, other ].each do |item|
        result = evaluate(@checklist, :member, item)
        assert_no_match(/peanuts/, [ result.summary, result.detail ].join)
      end
      assert_equal "Allergies is none of gluten", evaluate(@checklist, :member, none).summary
    end
  end

  test "last changed on or after" do
    with_fields do
      note = create_field("Emergency contact", :string)
      assign(:member, note, "Pat 555-0100")
      item = add_field_item(note, "filled_in", changed_since: "2026-09-01")

      travel_to(Time.zone.parse("2026-10-01")) { PersonFieldValue.where(person: person(:member)).update_all(updated_at: Time.current) }
      assert_equal "met", evaluate(@checklist, :member, item).status

      PersonFieldValue.where(person: person(:member)).update_all(updated_at: Time.zone.parse("2026-08-01"))
      result = evaluate(@checklist, :member, item)
      assert_equal "not_met", result.status
      assert_match "Not changed since", result.summary
    end
  end

  test "a deleted field is a problem and passes nobody" do
    with_fields do
      note = create_field("Old note", :string)
      item = add_field_item(note, "filled_in")
      assign(:member, note, "x")

      note.archive!
      assert_not note.destroy, "the item protects the field"
      assert_match "Used by the checklist Trip", note.errors.full_messages.to_sentence
      assert_includes @checklist.reload.problems.join, "archived"
      assert_equal "met", evaluate(@checklist, :member, item).status, "an archived field still has its values"

      item.update_columns(config: { "field_id" => SecureRandom.uuid, "operator" => "filled_in" })
      assert_includes @checklist.reload.problems.join, "was deleted"
      result = evaluate(@checklist, :member, item)
      assert_equal "not_met", result.status
      assert_match "deleted", result.summary
    end
  end

  test "the test must fit the field" do
    with_fields do
      note = create_field("Note", :string)
      hours = create_field("Hours", :integer)

      assert_not_nil add_field_item(note, "any_of", values: "x")
      assert_raises(ActiveRecord::RecordInvalid) { add_field_item(note, "at_least", number: 1) }
      assert_raises(ActiveRecord::RecordInvalid) { add_field_item(hours, "any_of", values: "x") }
      assert_raises(ActiveRecord::RecordInvalid) { add_field_item(note, "any_of") }
      assert_raises(ActiveRecord::RecordInvalid) { add_field_item(hours, "at_least") }
      assert_raises(ActiveRecord::RecordInvalid) { add_item(@checklist, :person_field, "None", { operator: "filled_in" }) }
    end
  end

  test "a batch gives the same answers as one person at a time" do
    with_fields do
      size = create_field("Size", :select, choices: %w[ S M L ])
      hours = create_field("Hours", :integer)
      assign(:member, size, "M")
      assign(:member2, size, "S")
      assign(:kid, hours, 8)
      items = [
        add_field_item(size, "any_of", values: "M"),
        add_field_item(size, "none_of", values: "M", blank: "met"),
        add_field_item(hours, "at_least", number: 5)
      ]
      names = %i[ member member2 kid rookie organizer ]

      batch = Checklists::Evaluator.new(@checklist.reload).call(names.map { |name| person(name).id })
      names.each do |name|
        single = Checklists::Evaluator.new(@checklist.reload).call([ person(name).id ])[person(name).id]
        items.each do |item|
          assert_equal single[item.id].status, batch.dig(person(name).id, item.id).status, "#{item.label} for #{name}"
          assert_equal single[item.id].summary, batch.dig(person(name).id, item.id).summary
        end
        assert_equal single[nil].status, batch.dig(person(name).id, nil).status
      end
    end
  end

  test "changing a value marks that person's stored results" do
    with_fields do
      note = create_field("Note", :string)
      add_field_item(note, "filled_in")
      refresh(@checklist)
      assert_equal "not_met", stored_status(@checklist, :member)

      assign(:member, note, "hello")

      assert ChecklistRefresh.where(checklist: @checklist, person_id: person(:member).id).exists?
      assert ChecklistResult.where(checklist: @checklist, person: person(:member)).all?(&:stale)
      assert_not ChecklistRefresh.where(checklist: @checklist, person_id: person(:rookie).id).exists?
    end
  end

  test "with person fields off, a custom field item is a problem and passes nobody" do
    note = nil
    with_fields do
      note = create_field("Note", :string)
      assign(:member, note, "hello")
      assert_equal "met", evaluate(@checklist, :member, add_field_item(note, "filled_in")).status
    end

    with_settings(feature_person_fields: "false", feature_checklists: "true") do
      item = @checklist.checklist_items.find_by!(label: "Note")
      result = evaluate(@checklist, :member, item)
      assert_equal "not_met", result.status
      assert_match "switched off", result.summary
      assert_includes @checklist.reload.problems.join, "switched off"
    end
  end

  test "last changed is refused on a built-in field" do
    with_fields do
      PersonField.ensure_system_fields!
      birthday = PersonField.system_field("birthday")

      error = assert_raises(ActiveRecord::RecordInvalid) { add_field_item(birthday, "filled_in", changed_since: "2026-09-01") }
      assert_match "built-in field", error.message
      item = add_field_item(birthday, "filled_in")
      item.update_columns(config: item.config.merge("changed_since" => "2026-09-01"))
      assert_includes @checklist.reload.problems.join, "built-in field"
      assert_equal "not_met", evaluate(@checklist, :kid, item).status
    end
  end

  test "values for a choice field must be among its choices" do
    with_fields do
      size = create_field("Size", :select, choices: %w[ S M XXL ])

      error = assert_raises(ActiveRecord::RecordInvalid) { add_field_item(size, "none_of", values: "XXLL") }
      assert_match "isn't one of Size's choices", error.message
      assert_not_nil add_field_item(size, "none_of", values: "xxl, s")
    end
  end
end
