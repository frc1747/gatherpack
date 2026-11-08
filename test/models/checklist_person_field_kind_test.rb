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
      after = add_field_item(physical, "on_or_after", date: { mode: "date", date: "2026-09-01" })
      before = add_field_item(physical, "on_or_before", date: { mode: "date", date: "2025-12-31" })

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
      item = add_field_item(birthday, "on_or_before", date: { mode: "date", date: "2015-01-01" })

      assert_equal "met", evaluate(@checklist, :kid, item).status
      assert_equal "not_met", evaluate(@checklist, :member, item).status, "no birthday"
    end
  end

  test "the fix says who may update the field, from its write level and whether they have a guardian" do
    with_fields do
      # The member has no guardian; the kid has one (their parent).
      expected = {
        "admin" => %w[leader leader], "leaders" => %w[leader leader], "self" => %w[person person],
        "self_and_leaders" => %w[person person], "guardians" => %w[leader guardian], "family" => %w[person guardian],
        "team" => %w[person guardian], "everyone" => %w[person person]
      }
      expected.each do |level, (member_by, kid_by)|
        field = create_field("Note #{level}", :string, read_permission: "everyone", write_permission: level)
        item = add_field_item(field, "filled_in")
        assert_equal member_by, evaluate(@checklist, :member, item).fix["by"], "#{level}, no guardian"
        assert_equal kid_by, evaluate(@checklist, :kid, item).fix["by"], "#{level}, with a guardian"
      end
    end
  end

  test "the kind's settings don't touch the database until the field choices are read" do
    with_fields do
      note = create_field("Note", :string)
      queries = []
      counter = ->(*, payload) { queries << payload[:sql] unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
      settings = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        Checklists.register_item_kind(:person_field, Checklists::Kinds::PersonField)
        Checklists::Kinds::PersonField.settings
      end

      assert_empty queries
      choice = settings.find { |setting| setting.key == :field_id }
      assert_includes choice.options, [ "Note", note.id ]
    end
  end

  test "missing data is not started unless the item says blank counts as met" do
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
      item = add_field_item(note, "filled_in", changed_since: { mode: "date", date: "2026-09-01" })

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

      error = assert_raises(ActiveRecord::RecordInvalid) { add_field_item(birthday, "filled_in", changed_since: { mode: "date", date: "2026-09-01" }) }
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

  test "dates can be relative: within the last N months, resolved from the as-of day" do
    with_fields do
      physical = create_field("Physical date", :date)
      note = create_field("Emergency contact", :string)
      assign(:member, physical, Date.new(2026, 6, 1))
      assign(:member2, physical, Date.new(2025, 6, 1))
      assign(:member, note, "Pat 555-0100")
      recent = add_field_item(physical, "on_or_after", date: { mode: "within", amount: 12, unit: "months" })
      current = add_field_item(note, "filled_in", changed_since: { mode: "within", amount: 30, unit: "days" })
      PersonFieldValue.where(person: person(:member), person_field: note).update_all(updated_at: Time.zone.parse("2026-10-20"))

      travel_to(Time.zone.parse("2026-11-06 12:00")) do
        assert_equal "met", evaluate(@checklist, :member, recent).status
        assert_equal "not_met", evaluate(@checklist, :member2, recent).status
        assert_equal "met", evaluate(@checklist, :member, current).status
        assert_equal "within the last 12 months", Checklists::Kinds::PersonField.relative(recent, "date").describe
        assert_equal "Physical date is within the last 12 months", recent.describe
      end
      travel_to(Time.zone.parse("2027-02-01 12:00")) do
        assert_equal "not_met", evaluate(@checklist, :member, current).status, "the 30 days ran out with no change"
      end
      assert_equal Time.zone.parse("2026-11-07 00:00"), Checklists::Kinds::PersonField.next_change_at(recent, Checklists::Context.new(@checklist, as_of: Time.zone.parse("2026-11-06 12:00")))
      fixed = add_field_item(physical, "on_or_after", date: { mode: "date", date: "2026-01-01" })
      assert_nil Checklists::Kinds::PersonField.next_change_at(fixed, Checklists::Context.new(@checklist, as_of: Time.zone.parse("2026-11-06 12:00")))
    end
  end

  # Visibility: a result is never visible to someone who can't read the field.
  def build_private_field
    @secret = create_field("Medical notes", :string, read_permission: "self_and_leaders", write_permission: "self_and_leaders")
    assign(:kid, @secret, "asthma")
    assign(:member, @secret, "none")
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @secret_item = add_field_item(@secret, "any_of", values: "asthma")
    refresh(@checklist)
  end

  test "a field's result is hidden from people who can't read the field" do
    with_fields do
      build_private_field
      visible = ->(viewer) { Checklists.status_for(@checklist, [ person(:kid) ], viewer: person(viewer))[person(:kid).id]&.item(@secret_item.id) }

      assert visible.call(:kid), "the person reads their own"
      assert visible.call(:admin)
      assert_nil visible.call(:parent), "a guardian isn't in a self-and-leaders field"
      assert_nil visible.call(:member2), "a teammate"
      assert_equal "met", evaluate(@checklist, :kid, @secret_item).status, "evaluation itself reads directly"
    end
  end

  test "organizers and grant holders don't get past the field's read level" do
    with_fields do
      build_private_field
      secret_team = create_field("Team notes", :string, read_permission: "admin", write_permission: "admin")
      assign(:kid, secret_team, "x")
      admin_only = add_field_item(secret_team, "filled_in")
      @checklist.checklist_grants.create!(badge: @viewer_badge, item_ids: [ @secret_item.id, admin_only.id ], access: :full)
      give_badge(:outsider, @viewer_badge)
      refresh(@checklist)

      [ :outsider, :organizer, :kid ].each do |viewer|
        status = Checklists.status_for(@checklist, [ person(:kid) ], viewer: person(viewer))[person(:kid).id]
        assert_nil status&.item(admin_only.id), "#{viewer} can't read an admin-only field"
      end
      assert_nil Checklists.status_for(@checklist, [ person(:kid) ], viewer: person(:outsider))[person(:kid).id]&.item(@secret_item.id)
      assert_not_nil Checklists.status_for(@checklist, [ person(:kid) ], viewer: person(:admin))[person(:kid).id].item(admin_only.id)
    end
  end

  test "a field with a team only shows for people it applies to" do
    with_fields do
      build_private_field
      crew_field = create_field("Crew notes", :string, read_permission: "everyone", write_permission: "admin", team: @crew)
      item = add_field_item(crew_field, "filled_in")
      ids = [ person(:kid).id, person(:organizer).id ]

      visible = Checklists::Kinds::PersonField.visible_person_ids(item, person(:member), ids)
      assert_equal [ person(:organizer).id ], visible, "Kid isn't on the field's team"
      assert Checklists::Kinds::PersonField.visible_to?(item, person(:member), person(:organizer))
      assert_not Checklists::Kinds::PersonField.visible_to?(item, person(:member), person(:kid))
    end
  end

  test "an author can't set up a test on a field they can't read for everyone covered" do
    with_fields do
      build_private_field
      mine = Checklists::Kinds::PersonField
      item = @checklist.checklist_items.new(kind: "person_field", label: "Notes")
      item.config_params = { field_id: @secret.id, operator: "filled_in" }

      assert mine.authorable_by?(item, person(:admin))
      assert_not mine.authorable_by?(item, person(:parent))
      assert mine.authorable_by?(item, person(:club_manager)), "a leader of everyone covered"
      assert_not mine.authorable_by?(item, person(:crew_manager)), "a manager who doesn't lead everyone covered"

      open_field = create_field("Open", :string, read_permission: "everyone", write_permission: "admin")
      open_item = @checklist.checklist_items.new(kind: "person_field", label: "Open")
      open_item.config_params = { field_id: open_field.id, operator: "filled_in" }
      assert mine.authorable_by?(open_item, person(:parent))
    end
  end

  test "the overall and an any-of group don't give away a hidden field's answer" do
    with_fields do
      build_private_field
      group = add_item(@checklist, :any_of, "Either")
      add_item(@checklist, :person_field, "Notes", { field_id: @secret.id, operator: "any_of", values: "asthma" }, parent: group)
      add_item(@checklist, :has_login, "Login", {}, parent: group)
      add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
      refresh(@checklist)
      seen = ->(viewer) { Checklists.status_for(@checklist, [ person(:kid) ], viewer: person(viewer))[person(:kid).id] }

      assert_equal 1, seen.call(:kid).overall.measures["unmet"], "only Safety is left to do"
      assert_nil seen.call(:parent).item(@secret_item.id)
      assert_nil seen.call(:parent).item(group.id), "a group holding the hidden item is hidden too"
      assert_nil seen.call(:parent).item(group.children.first.id)
      assert_equal 1, seen.call(:parent).overall.measures["unmet"]
    end
  end

  test "a checklist whose only item is a hidden field doesn't show the parent an overall" do
    with_fields do
      build_private_field
      status = Checklists.status_for(@checklist, [ person(:kid) ], viewer: person(:parent))[person(:kid).id]

      assert_nil status, "nothing is left to show the parent"
      assert_nil Checklists.status_for(@checklist, [ person(:kid) ], viewer: person(:member2))[person(:kid).id]
      assert_equal "met", Checklists.status_for(@checklist, [ person(:kid) ], viewer: person(:kid))[person(:kid).id].overall.status.to_s
    end
  end

  test "an impact check doesn't name people moved by a field the viewer can't read" do
    with_fields do
      build_private_field
      with_settings(checklists_organizers: "Checklist Organizer > Club") do
        @checklist.checklist_organizers.create!(person: person(:organizer))
        gone = []
        impact = Checklists::Impact.new(@checklist, items: gone, viewer: person(:organizer))

        assert_empty impact.moves.flat_map(&:names), "the organizer doesn't lead anyone whose answer moves"
        assert_operator impact.hidden, :>=, 3, "Member, MemberTwo and Rookie would move, counted only as hidden"
        assert_match "through an item you can't see", impact.sentences.join
        full = Checklists::Impact.new(@checklist, items: gone, viewer: person(:admin))
        assert_includes full.moves.flat_map(&:names).join, "Rookie"
      end
    end
  end

  test "the item form offers only fields the author can read" do
    with_fields do
      create_field("Open", :string, read_permission: "everyone", write_permission: "admin")
      create_field("Admin only", :string, read_permission: "admin", write_permission: "admin")
      create_field("Leaders", :string, read_permission: "self_and_leaders", write_permission: "self_and_leaders")
      names = ->(author) { Checklists::Kinds::PersonField.settings_for(author).first.options.map(&:first) }

      assert_equal [ "Admin only", "Leaders", "Open" ], names.call(person(:admin)).sort
      assert_equal [ "Leaders", "Open" ], names.call(person(:club_manager)).sort
      assert_equal [ "Leaders", "Open" ], names.call(person(:outsider)).sort, "everyone can read their own"
      assert_not_includes names.call(person(:club_manager)), "Admin only"
      assert_equal 3, names.call(nil).size
    end
  end
end
