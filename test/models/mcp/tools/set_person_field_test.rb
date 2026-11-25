require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::SetPersonFieldTest < ActiveSupport::TestCase
  include McpWorld

  ADULT = Date.new(1980, 1, 1)

  setup do
    build_mcp_world
    @restore_person_fields = apply_settings(feature_person_fields: "true")
    PersonField.ensure_system_fields!
    @subject = person(:alpha_member)
    @subject.update!(birthday: ADULT)

    @notes = PersonField.create!(name: "Notes", data_type: :text, read_permission: :leaders, write_permission: :leaders)
    @admin_only = PersonField.create!(name: "Eligible", data_type: :boolean, read_permission: :everyone, write_permission: :admin)
    @self_field = PersonField.create!(name: "Nickname", data_type: :string, read_permission: :everyone, write_permission: :self)
    @family = PersonField.create!(name: "Allergies", data_type: :text, read_permission: :family, write_permission: :family)

    @guardian = create_world_person("AlphaGuardian", @alpha)
    minor = RelationshipType.create!(parent_label: "Guardian of", child_label: "Ward of", permission: :added_by_admin, guardianship: :minor)
    Relationship.create!(parent: @guardian, child: @subject, relationship_type: minor, created_by: person(:admin))
  end

  teardown { @restore_person_fields&.call }

  def set(viewer, field, value, target: @subject, **options)
    key = field.respond_to?(:key) ? field.key : field
    call_tool("set_person_field", user: viewer.is_a?(Symbol) ? user(viewer) : viewer, person_id: target.neat_id, field_key: key, value: value, **options)
  end

  def stored(field, target = @subject)
    Person.find(target.id).field_value(field)
  end

  def built_in(source)
    PersonField.find_by!(system_source: source)
  end

  test "an admin sets a field and gets the new value" do
    result = set(:admin, @notes, "Quiet")

    assert_nil result.error
    assert_equal "Quiet", stored(@notes)
    assert_equal({ "id" => @subject.neat_id, "name" => "AlphaMember World" }, result.value["person"])
    assert_equal({ "key" => "notes", "name" => "Notes", "type" => "text", "value" => "Quiet", "changed" => true }, result.value.except("person"))
    assert_equal @subject.person_field_values.find_by!(person_field: @notes), result.changed
  end

  test "each field's write level decides who can set it" do
    allowed = {
      @notes => [ :admin, :alpha_manager ],
      @admin_only => [ :admin ],
      @self_field => [ :admin, :alpha_member ],
      @family => [ :admin, :alpha_manager, :alpha_member ]
    }
    allowed.each do |field, viewers|
      [ :admin, :alpha_manager, :alpha_member, :ward, :beta_member ].each do |viewer|
        @subject.set_field_value(field, nil)
        value = field == @admin_only ? true : "From #{viewer}"
        result = set(viewer, field, value)
        if viewers.include?(viewer)
          assert_nil result.error, "#{viewer} on #{field.key}"
          assert_equal value, stored(field), "#{viewer} on #{field.key}"
        else
          assert_includes [ "Not allowed", "Not found" ], result.error, "#{viewer} on #{field.key}"
          assert_not_equal value, stored(field), "#{viewer} on #{field.key}"
        end
      end
    end
  end

  test "a guardian sets a family field but not a leaders field" do
    assert_nil set(@guardian.user, @family, "Nuts").error
    assert_equal "Nuts", stored(@family)
    assert_equal "Not allowed", set(@guardian.user, @notes, "No").error
    assert_nil stored(@notes)
  end

  test "a badge with write access can set the field, one with read access can't" do
    writer = create_world_person("Writer", @alpha)
    reader = create_world_person("Reader", @alpha)
    write_badge = create_world_badge("Field Writer")
    read_badge = create_world_badge("Field Reader")
    BadgeAssignment.create!(badge: write_badge, person: writer)
    BadgeAssignment.create!(badge: read_badge, person: reader)
    PersonFieldBadgeGrant.create!(person_field: @admin_only, badge: write_badge, access: :write)
    PersonFieldBadgeGrant.create!(person_field: @admin_only, badge: read_badge, access: :read)

    assert_equal "Not allowed", set(reader.user, @admin_only, true).error
    assert_nil set(writer.user, @admin_only, true).error
    assert_equal true, stored(@admin_only)
  end

  test "a field the viewer can't write and a key that doesn't exist read the same" do
    refused = set(:alpha_member, @notes, "x")
    unknown = set(:alpha_member, "no_such_field", "x")

    assert_equal "Not allowed", refused.error
    assert_equal refused.error, unknown.error
    assert_equal refused.outcome, unknown.outcome
  end

  test "someone the viewer can't see is not found" do
    assert_equal "Not found", set(:beta_member, @self_field, "x", target: person(:alpha_member)).error
  end

  test "archived fields, and a team's field on someone outside it, can't be set" do
    @self_field.update!(archived_at: Time.current)
    assert_equal "Not allowed", set(:admin, @self_field, "x").error

    team_field = PersonField.create!(name: "Beta Only", data_type: :string, read_permission: :everyone, write_permission: :everyone, team: @beta)
    assert_equal "Not allowed", set(:admin, team_field, "x").error
  end

  test "account email stays read only" do
    assert_equal "Not allowed", set(:admin, built_in("user.email"), "new@example.com").error
    assert_not_equal "new@example.com", @subject.user.reload.email
  end

  test "values follow the field's type, as the form does" do
    integer = PersonField.create!(name: "Locker", data_type: :integer, read_permission: :everyone, write_permission: :admin, min: "1", max: "10")
    date = PersonField.create!(name: "Physical", data_type: :date, read_permission: :everyone, write_permission: :admin)
    select = PersonField.create!(name: "Size", data_type: :select, choices_text: "S\nM", read_permission: :everyone, write_permission: :admin)
    many = PersonField.create!(name: "Sports", data_type: :multi_select, choices_text: "Golf\nTennis", read_permission: :everyone, write_permission: :admin)

    assert_equal 5, set(:admin, integer, 5).value["value"]
    assert_equal "2026-05-01", set(:admin, date, "2026-05-01").value["value"]
    assert_equal "M", set(:admin, select, "M").value["value"]
    assert_equal %w[Golf Tennis], set(:admin, many, %w[Golf Tennis]).value["value"]
    assert_equal [ "Golf" ], set(:admin, many, "Golf").value["value"]
    assert_equal true, set(:admin, @admin_only, true).value["value"]
    assert_equal false, set(:admin, @admin_only, false).value["value"]

    { integer => [ "soon", 99 ], date => [ "someday" ], select => [ "XL" ], many => [ [ "Chess" ] ], @notes => [ [ "a", "b" ] ] }.each do |field, values|
      values.each do |value|
        before = stored(field)
        result = set(:admin, field, value)
        assert_equal "error", result.outcome.to_s, "#{field.key}: #{value.inspect}"
        assert_not_equal "Internal error", result.error, "#{field.key}: #{value.inspect}"
        assert before == stored(field), "#{field.key}: #{value.inspect}"
        assert_nil result.changed
      end
    end
  end

  test "a yes/no field takes only true, false or null, so 'no' can't store Yes" do
    set(:admin, @admin_only, true)

    [ "no", "No", "nope", "false", "0", 0, 1, 1.5 ].each do |value|
      result = set(:admin, @admin_only, value)
      assert result.error?, value.inspect
      assert_equal true, stored(@admin_only), value.inspect
    end
    assert_equal false, set(:admin, @admin_only, nil).value["value"]
  end

  test "values the form couldn't send are refused" do
    many = PersonField.create!(name: "Sports", data_type: :multi_select, choices_text: "Golf\nTennis", read_permission: :everyone, write_permission: :admin)
    line = PersonField.create!(name: "Nickname Two", data_type: :string, read_permission: :everyone, write_permission: :admin)
    set(:admin, many, [ "Golf" ])

    [ [ nil ], [ "" ], [ [ "Golf" ] ], [ { "a" => 1 } ], 5 ].each do |value|
      assert set(:admin, many, value).error?, value.inspect
      assert_equal [ "Golf" ], stored(many), value.inspect
    end
    [ true, 12, 1.5, Float::INFINITY, "a\nb", "a\u0007b" ].each do |value|
      assert set(:admin, line, value).error?, value.inspect
      assert_nil stored(line), value.inspect
    end
    assert_nil set(:admin, @notes, "two\nlines").error
    assert_equal "two\nlines", stored(@notes)
  end

  test "an empty list clears a multiple-choice field" do
    many = PersonField.create!(name: "Sports", data_type: :multi_select, choices_text: "Golf\nTennis", read_permission: :everyone, write_permission: :admin)
    set(:admin, many, [ "Golf" ])

    assert_nil set(:admin, many, []).error
    assert_nil stored(many)
    assert_not @subject.person_field_values.exists?(person_field: many)
  end

  test "the error doesn't name a required field withheld from a minor" do
    @subject.update!(birthday: 10.years.ago.to_date)
    PersonField.create!(name: "Emergency Phone", data_type: :phone, read_permission: :everyone, write_permission: :admin, required: true)

    result = set(:admin, @notes, "Quiet")

    assert_equal "Another required field is blank; complete it on their profile page.", result.error
    assert_nil stored(@notes)
  end

  test "a required field can't be cleared, and the error names it" do
    required = PersonField.create!(name: "Must Have", data_type: :string, read_permission: :everyone, write_permission: :admin, required: true)
    Person.find(@subject.id).set_field_value(required, "Kept")

    assert_match(/Must have can't be blank/i, set(:admin, required, nil).error)
    assert_equal "Kept", stored(required)
  end

  test "clearing an adult's required birthday names the birthday, and changes nothing" do
    built_in("birthday").update!(required: true)

    assert_match(/Birthday can't be blank/, set(:admin, built_in("birthday"), nil).error)
    assert_equal ADULT, Person.find(@subject.id).birthday
  end

  test "someone who can't write an adult's built-in fields is refused" do
    [ [ "phone_number", "555-0199" ], [ "address", "2 Elm St" ], [ "birthday", "1981-02-03" ] ].each do |source, value|
      field = built_in(source)
      field.update!(read_permission: :everyone, write_permission: :leaders)
      before = stored(field)

      [ :alpha_member, :ward, :beta_member ].each do |viewer|
        assert_includes [ "Not allowed", "Not found" ], set(viewer, field, value).error, "#{viewer} on #{source}"
        assert before == stored(field), "#{viewer} on #{source}"
      end
      assert_nil set(:alpha_manager, field, value).error, source
    end
  end

  test "a built-in field's change points at the person" do
    assert_equal @subject, set(:admin, built_in("address"), "2 Elm St").changed
  end

  test "clearing a custom field still points at the removed row" do
    set(:admin, @notes, "Quiet")
    row = @subject.person_field_values.find_by!(person_field: @notes)

    assert_equal row.id, set(:admin, @notes, nil).changed.id
  end

  test "an object isn't accepted as a value" do
    result = set(:admin, @notes, { "a" => 1 })

    assert result.error?
    assert_nil stored(@notes)
  end

  test "null clears a field" do
    set(:admin, @notes, "Quiet")
    result = set(:admin, @notes, nil)

    assert_nil result.error
    assert_nil result.value["value"]
    assert_nil stored(@notes)
    assert_not @subject.person_field_values.exists?(person_field: @notes)
  end

  test "a value argument is required, so a slip doesn't clear a field" do
    set(:admin, @notes, "Quiet")
    result = call_tool("set_person_field", user: user(:admin), person_id: @subject.neat_id, field_key: @notes.key)

    assert result.error?
    assert_equal "Quiet", stored(@notes)
  end

  test "setting the same value changes nothing and says so" do
    set(:admin, @notes, "Quiet")
    tool = Mcp.tool("set_person_field")
    result = with_settings(mcp_write_enabled: "true") do
      tool.run(mcp_context(user(:admin), scopes: "mcp_write"), { "person_id" => @subject.neat_id, "field_key" => @notes.key, "value" => "Quiet" })
    end

    assert_nil result.error
    assert_equal false, result.value["changed"]
    assert_nil result.changed
  end

  test "a blank required field blocks the save, as it does on the page" do
    PersonField.create!(name: "Must Have", data_type: :string, read_permission: :everyone, write_permission: :admin, required: true)

    result = set(:admin, @notes, "Quiet")

    assert_match(/can't be blank/, result.error)
    assert_nil stored(@notes)
  end

  test "a minor's contact details can't be set, whoever is asking" do
    @subject.update!(birthday: 10.years.ago.to_date, phone_number: "555-0100", address: "1 Main St")
    emergency = PersonField.create!(name: "Emergency Phone", data_type: :phone, read_permission: :everyone, write_permission: :everyone)
    other_email = PersonField.create!(name: "Other Email", data_type: :email, read_permission: :everyone, write_permission: :everyone)

    [ user(:admin), user(:alpha_manager), user(:alpha_member), @guardian.user ].each do |viewer|
      [ [ built_in("phone_number"), "555-0199" ], [ built_in("address"), "2 Elm St" ], [ built_in("birthday"), "1980-01-01" ],
        [ emergency, "555-0123" ], [ other_email, "kid@example.net" ] ].each do |field, value|
        before = stored(field)
        assert_equal "Not allowed", set(viewer, field, value).error, "#{viewer.email} on #{field.key}"
        assert before == stored(field), "#{viewer.email} on #{field.key}"
      end
    end
  end

  test "someone with no birthday on file counts as a minor here too" do
    @subject.update!(birthday: nil)

    assert_equal "Not allowed", set(:admin, built_in("birthday"), "1980-01-01").error
    assert_nil Person.find(@subject.id).birthday
  end

  test "a minor's other fields can still be set" do
    @subject.update!(birthday: 10.years.ago.to_date)

    assert_nil set(:alpha_manager, @notes, "Quiet").error
    assert_equal "Quiet", stored(@notes)
  end

  test "an adult's contact details can be set by those the field allows" do
    result = set(:admin, built_in("phone_number"), "555-0199")

    assert_nil result.error
    assert_equal "555-0199", Person.find(@subject.id).phone_number
    assert_equal "555-0199", result.value["value"]
  end

  test "a read token and the setting being off refuse it, and so does the feature" do
    assert_equal "Not allowed", set(:admin, @notes, "x", scopes: "mcp_read").error
    assert_equal "Writes disabled", set(:admin, @notes, "x", writes_enabled: false).error
    with_feature(:person_fields, false) { assert_equal "Feature off", set(:admin, @notes, "x").error }
    assert_nil stored(@notes)
  end

  test "it records who changed the value and is logged" do
    assert_difference -> { McpToolCall.where(tool: "set_person_field", outcome: "ok").count } do
      set(:alpha_manager, @notes, "Quiet")
    end

    row = @subject.person_field_values.find_by!(person_field: @notes)
    assert_equal person(:alpha_manager), row.updated_by
    assert_equal user(:alpha_manager).id.to_s, row.versions.last.whodunnit.to_s
    call = McpToolCall.where(tool: "set_person_field").order(:id).last
    assert_equal "PersonFieldValue", call.changed_type
    assert_equal @subject.person_field_values.find_by!(person_field: @notes).id, call.changed_id
  end

  test "the value changed hook runs, as on the page" do
    Thread.current[:mcp_field_change] = nil
    Hook.create!(name: "MCP field hook", event: "person_fields - value changed",
      code: "Thread.current[:mcp_field_change] = [ model.key, model.old_value, model.new_value, model.changed_by.id ]")

    set(:alpha_manager, @notes, "Quiet")

    assert_equal [ "notes", nil, "Quiet", person(:alpha_manager).id ], Thread.current[:mcp_field_change]
  ensure
    Thread.current[:mcp_field_change] = nil
  end
end
