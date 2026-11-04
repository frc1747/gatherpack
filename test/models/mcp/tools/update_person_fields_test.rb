require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::UpdatePersonFieldsTest < ActiveSupport::TestCase
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
    @size = PersonField.create!(name: "Jacket", data_type: :select, choices_text: "S\nM\nL", read_permission: :everyone, write_permission: :admin)

    @guardian = create_world_person("AlphaGuardian", @alpha)
    minor = RelationshipType.create!(parent_label: "Guardian of", child_label: "Ward of", permission: :added_by_admin, guardianship: :minor)
    Relationship.create!(parent: @guardian, child: @subject, relationship_type: minor, created_by: person(:admin))
  end

  teardown { @restore_person_fields&.call }

  def update(viewer, values, target: @subject, **options)
    call_tool("update_person_fields", user: viewer.is_a?(Symbol) ? user(viewer) : viewer, person_id: target.neat_id, values: values, **options)
  end

  def stored(field, target = @subject)
    Person.find(target.id).field_value(field)
  end

  def built_in(source)
    PersonField.find_by!(system_source: source)
  end

  def run_with_writes(viewer, arguments)
    with_settings(mcp_write_enabled: "true") do
      Mcp.tool("update_person_fields").run(mcp_context(user(viewer), scopes: "mcp_write"), arguments)
    end
  end

  # The result of update, which must change no value row, no person and no audit row.
  def assert_unchanged(viewer, values, target: @subject)
    result = nil
    assert_no_difference [ -> { PersonFieldValue.count }, -> { AuditLog.count }, -> { target.reload.updated_at.to_f } ] do
      result = update(viewer, values, target: target)
    end
    assert result.error?, "expected a refusal for #{values.inspect}"
    assert_nil result.changed
    result
  end

  test "an admin sets several fields and gets the person's fields back" do
    result = update(:admin, { "notes" => "Quiet", "eligible" => true, "nickname" => "Sam", "jacket" => "M" })

    assert_nil result.error
    assert_equal [ "Quiet", true, "Sam", "M" ], [ @notes, @admin_only, @self_field, @size ].map { |field| stored(field) }
    assert_equal({ "id" => @subject.neat_id, "name" => "AlphaMember World" }, result.value["person"])
    assert_equal get_fields(:admin), result.value["groups"]
    assert_equal 4, result.changed_records.size
    assert_equal result.changed_records.first, result.changed
  end

  def get_fields(viewer)
    call_tool("get_person_fields", user: user(viewer), person_id: @subject.neat_id).value["groups"]
  end

  test "only the given fields change" do
    @subject.set_field_value(@notes, "Kept")
    @subject.set_field_value(@family, "Peanuts")

    assert_nil update(:admin, { "nickname" => "Sam" }).error

    assert_equal [ "Kept", "Peanuts", "Sam" ], [ stored(@notes), stored(@family), stored(@self_field) ]
  end

  test "null clears a field and an empty list clears a multiple-choice field" do
    many = PersonField.create!(name: "Sports", data_type: :multi_select, choices_text: "Golf\nTennis", read_permission: :everyone, write_permission: :admin)
    @subject.set_field_value(@notes, "Quiet")
    @subject.set_field_value(many, [ "Golf" ])

    result = update(:admin, { "notes" => nil, "sports" => [] })

    assert_nil result.error
    assert_nil stored(@notes)
    assert_nil stored(many)
    assert_equal [ @notes.id, many.id ].sort, result.changed_records.map(&:person_field_id).sort
  end

  test "each field's write level decides who can set it" do
    allowed = { "notes" => %i[admin alpha_manager], "eligible" => %i[admin], "nickname" => %i[admin alpha_member], "allergies" => %i[admin alpha_manager alpha_member] }
    values = { "notes" => "x", "eligible" => true, "nickname" => "x", "allergies" => "x" }
    fields = { "notes" => @notes, "eligible" => @admin_only, "nickname" => @self_field, "allergies" => @family }

    allowed.each do |key, viewers|
      %i[admin alpha_manager alpha_member ward beta_member].each do |viewer|
        @subject.set_field_value(fields[key], nil)
        result = update(viewer, { key => values[key] })

        if viewers.include?(viewer)
          assert_nil result.error, "#{viewer} on #{key}"
          assert stored(fields[key]).present?, "#{viewer} on #{key}"
        else
          assert_includes [ "Not allowed: #{key}", "Not found" ], result.error, "#{viewer} on #{key}" unless viewer == :ward
          assert_equal "Not allowed", result.error, "#{viewer} on #{key}" if viewer == :ward
          assert_empty Array(stored(fields[key]).presence), "#{viewer} on #{key}"
        end
      end
    end
  end

  test "a guardian sets a family field but not a leaders field" do
    assert_nil update(@guardian.user, { "allergies" => "Peanuts" }).error
    assert_equal "Peanuts", stored(@family)

    assert_equal "Not allowed: notes", assert_unchanged(@guardian.user, { "notes" => "x" }).error
  end

  test "one refused key refuses every key, and names each of them" do
    @subject.set_field_value(@family, "Before")

    result = assert_unchanged(:alpha_manager, { "allergies" => "After", "eligible" => true, "no_such_field" => "x", "nickname" => "y" })

    assert_equal "Not allowed: eligible, no_such_field, and nickname", result.error
    assert_equal "denied", result.outcome.to_s
    assert_equal "Before", stored(@family)
    assert_equal false, stored(@admin_only)
  end

  test "a field that doesn't exist, one the viewer can't write and one that is archived read the same" do
    @self_field.update!(archived_at: Time.current)
    team_field = PersonField.create!(name: "Beta Only", data_type: :string, read_permission: :everyone, write_permission: :everyone, team: @beta)

    messages = [ "no_such_field", "eligible", "nickname", "beta_only" ].map { |key| assert_unchanged(:alpha_manager, { key => "x" }).error }

    assert_equal [ "Not allowed: no_such_field", "Not allowed: eligible", "Not allowed: nickname", "Not allowed: beta_only" ], messages
    assert_nil stored(team_field)
  end

  test "someone the viewer can't see is not found" do
    assert_equal "Not found", assert_unchanged(:beta_member, { "nickname" => "x" }).error
  end

  test "values that fail the form's rules refuse everything, and name the field" do
    @subject.set_field_value(@notes, "Before")

    result = assert_unchanged(:admin, { "notes" => "After", "jacket" => "XL" })

    assert_match(/Jacket isn't one of the choices/, result.error)
    assert_equal "Before", stored(@notes)
  end

  test "values follow the field's type, as the form does" do
    integer = PersonField.create!(name: "Locker", data_type: :integer, read_permission: :everyone, write_permission: :admin, min: "1", max: "10")
    date = PersonField.create!(name: "Physical", data_type: :date, read_permission: :everyone, write_permission: :admin)
    many = PersonField.create!(name: "Sports", data_type: :multi_select, choices_text: "Golf\nTennis", read_permission: :everyone, write_permission: :admin)

    assert_nil update(:admin, { "locker" => 5, "physical" => "2026-05-01", "sports" => %w[Golf Tennis], "eligible" => false }).error
    assert_equal [ 5, Date.new(2026, 5, 1), %w[Golf Tennis], false ], [ stored(integer), stored(date), stored(many), stored(@admin_only) ]

    [ { "locker" => "soon" }, { "locker" => 99 }, { "locker" => 1.5 }, { "physical" => "someday" }, { "physical" => 20_260_501 },
      { "sports" => [ "Chess" ] }, { "sports" => [ nil ] }, { "sports" => [ [ "Golf" ] ] }, { "sports" => 5 }, { "notes" => [ "a", "b" ] },
      { "notes" => { "a" => 1 } }, { "nickname" => "a\nb" }, { "nickname" => true } ].each do |values|
      result = assert_unchanged(:admin, values)
      assert_not_equal "Internal error", result.error, values.inspect
    end
  end

  test "a yes/no field takes only true, false or null, so 'no' can't store Yes" do
    update(:admin, { "eligible" => true })

    [ "no", "No", "false", "0", 0, 1, 0.0 ].each do |value|
      assert update(:admin, { "eligible" => value }).error?, value.inspect
      assert_equal true, stored(@admin_only), value.inspect
    end
    assert_nil update(:admin, { "eligible" => false }).error
    assert_equal false, stored(@admin_only)
  end

  test "a number that is not finite is refused, not an internal error" do
    integer = PersonField.create!(name: "Locker", data_type: :integer, read_permission: :everyone, write_permission: :admin)

    [ Float::INFINITY, -Float::INFINITY, Float::NAN ].each do |value|
      result = assert_unchanged(:admin, { "locker" => value })
      assert_not_equal "Internal error", result.error, value.inspect
    end
    assert_nil stored(integer)
  end

  test "the arguments must be an object of values, and nothing else is accepted" do
    @subject.set_field_value(@notes, "Kept")

    [ {}, { "person_id" => @subject.neat_id }, { "person_id" => @subject.neat_id, "values" => {} },
      { "person_id" => @subject.neat_id, "values" => "notes" }, { "person_id" => @subject.neat_id, "values" => [ "notes" ] },
      { "person_id" => @subject.neat_id, "values" => { "notes" => "x" }, "value" => "y" },
      { "person_id" => @subject.neat_id, "values" => { "notes" => "x\u0000y" } } ].each do |arguments|
      result = run_with_writes(:admin, arguments)
      assert result.error?, arguments.inspect
      assert_not_equal "Internal error", result.error, arguments.inspect
    end
    assert_equal "Kept", stored(@notes)
  end

  test "a required field can't be cleared, and the error names it" do
    required = PersonField.create!(name: "Must Have", data_type: :string, read_permission: :everyone, write_permission: :admin, required: true)
    @subject.set_field_value(required, "Kept")

    result = assert_unchanged(:admin, { "must_have" => nil, "notes" => "x" })

    assert_match(/Must have can't be blank/i, result.error)
    assert_equal "Kept", stored(required)
    assert_nil stored(@notes)
  end

  test "a blank required field elsewhere blocks the change, as it does on the page" do
    PersonField.create!(name: "Must Have", data_type: :string, read_permission: :everyone, write_permission: :admin, required: true)

    assert_match(/can't be blank/, assert_unchanged(:admin, { "notes" => "x" }).error)
  end

  test "clearing an adult's required birthday names the birthday" do
    built_in("birthday").update!(required: true)

    assert_match(/Birthday can't be blank/, assert_unchanged(:admin, { "birthday" => nil }).error)
    assert_equal ADULT, Person.find(@subject.id).birthday
  end

  test "built-in fields for an adult follow their write levels, in one call" do
    assert_nil update(:admin, { "phone" => "555-0199", "address" => "2 Elm St", "birthday" => "1981-02-03", "notes" => "x" }).error
    reloaded = Person.find(@subject.id)
    assert_equal [ "555-0199", "2 Elm St", Date.new(1981, 2, 3) ], [ reloaded.phone_number, reloaded.address, reloaded.birthday ]

    [ "phone_number", "address", "birthday" ].each { |source| built_in(source).update!(read_permission: :everyone, write_permission: :leaders) }
    assert_equal "Not allowed", assert_unchanged(:ward, { "phone" => "555-0100" }).error
    %i[alpha_member beta_member].each do |viewer|
      assert_includes [ "Not allowed: phone, address, and birthday", "Not found" ], assert_unchanged(viewer, { "phone" => "555-0100", "address" => "3 Oak", "birthday" => "1990-01-01" }).error
    end
    assert_nil update(:alpha_manager, { "phone" => "555-0100", "address" => "3 Oak" }).error
  end

  test "the account email is not writable for anyone" do
    assert_equal "Not allowed: email", assert_unchanged(:admin, { "email" => "new@example.com", "notes" => "x" }).error
    assert_not_equal "new@example.com", @subject.user.reload.email
  end

  test "a minor's contact details are refused by name, whoever is asking, and so is the rest of the call" do
    @subject.update!(birthday: 10.years.ago.to_date, phone_number: "555-0100", address: "1 Main St")
    emergency = PersonField.create!(name: "Emergency Phone", data_type: :phone, read_permission: :everyone, write_permission: :everyone)
    PersonField.create!(name: "Other Email", data_type: :email, read_permission: :everyone, write_permission: :everyone)

    [ user(:admin), user(:alpha_manager), user(:alpha_member), @guardian.user ].each do |viewer|
      result = assert_unchanged(viewer, { "notes" => "x", "allergies" => "y", "phone" => "555-0199", "address" => "2 Elm St", "birthday" => "1980-01-01",
                                          "emergency_phone" => "555-0123", "other_email" => "kid@example.net" })
      assert_match(/phone, address, birthday, emergency_phone, and other_email\z/, result.error)
    end
    assert_equal "555-0100", Person.find(@subject.id).phone_number
    assert_nil stored(emergency)
  end

  test "someone with no birthday on file counts as a minor" do
    @subject.update!(birthday: nil)

    assert_equal "Not allowed: birthday", assert_unchanged(:admin, { "birthday" => "1980-01-01" }).error
    assert_nil Person.find(@subject.id).birthday
  end

  test "a minor's other fields can still be set, several at once" do
    @subject.update!(birthday: 10.years.ago.to_date)

    assert_nil update(:alpha_manager, { "notes" => "Quiet", "allergies" => "Peanuts" }).error
    assert_equal [ "Quiet", "Peanuts" ], [ stored(@notes), stored(@family) ]
  end

  test "the error doesn't name a required field withheld from a minor" do
    @subject.update!(birthday: 10.years.ago.to_date)
    PersonField.create!(name: "Emergency Phone", data_type: :phone, read_permission: :everyone, write_permission: :admin, required: true)

    result = assert_unchanged(:admin, { "notes" => "Quiet" })

    assert_equal "Another required field is blank; complete it on their profile page.", result.error
  end

  test "setting what is already there changes nothing and says nothing changed" do
    update(:admin, { "notes" => "Quiet" })

    result = run_with_writes(:admin, { "person_id" => @subject.neat_id, "values" => { "notes" => "Quiet" } })

    assert_nil result.error
    assert_nil result.changed
    assert_empty result.changed_records
  end

  test "only the fields that changed are recorded as changed" do
    update(:admin, { "notes" => "Quiet" })

    result = update(:admin, { "notes" => "Quiet", "nickname" => "Sam", "phone" => "555-0199" })

    assert_nil result.error
    assert_equal [ "PersonFieldValue", "Person" ], result.changed_records.map { |record| record.class.name }
    assert_equal @subject, result.changed_records.last
  end

  test "a read token, writes being off and the feature being off refuse it" do
    assert_equal "Not allowed", update(:admin, { "notes" => "x" }, scopes: "mcp_read").error
    assert_equal "Writes disabled", update(:admin, { "notes" => "x" }, writes_enabled: false).error
    with_feature(:person_fields, false) { assert_equal "Feature off", update(:admin, { "notes" => "x" }).error }
    assert_nil stored(@notes)
  end

  test "it records who changed the values" do
    update(:alpha_manager, { "notes" => "Quiet", "allergies" => "Peanuts" })

    [ @notes, @family ].each do |field|
      row = @subject.person_field_values.find_by!(person_field: field)
      assert_equal person(:alpha_manager), row.updated_by
      assert_equal user(:alpha_manager).id.to_s, row.versions.last.whodunnit.to_s
    end
  end

  test "the call log keeps the keys and masks every value" do
    update(:admin, { "notes" => "Private note", "eligible" => true, "phone" => "555-867-5309" })

    call = McpToolCall.where(tool: "update_person_fields").order(:id).last
    assert_equal({ "notes" => "[masked]", "eligible" => "[masked]", "phone" => "[masked]" }, call.arguments["values"])
    assert_not_includes call.arguments.to_json, "555-867-5309"
    assert_equal "ok", call.outcome
    assert_equal 3, call.changed_records.size
  end

  test "a refused call is logged with its values masked" do
    update(:alpha_manager, { "eligible" => true, "notes" => "Private note" })

    call = McpToolCall.where(tool: "update_person_fields").order(:id).last
    assert_equal "denied", call.outcome
    assert_not_includes call.arguments.to_json, "Private note"
    assert_equal %w[eligible notes], call.arguments["values"].keys.sort
  end

  test "values that aren't an object are masked whole in the log" do
    run_with_writes(:admin, { "person_id" => @subject.neat_id, "values" => "Private note" })

    assert_not_includes McpToolCall.where(tool: "update_person_fields").order(:id).last.arguments.to_json, "Private note"
  end

  test "the value changed hook runs for each changed field, as on the page" do
    seen = []
    Thread.current[:mcp_field_changes] = seen
    Hook.create!(name: "MCP field hook", event: "person_fields - value changed",
      code: "Thread.current[:mcp_field_changes] << [ model.key, model.old_value, model.new_value, model.changed_by.id ]")

    update(:alpha_manager, { "notes" => "Quiet", "allergies" => "Peanuts" })

    assert_equal [ [ "allergies", nil, "Peanuts", person(:alpha_manager).id ], [ "notes", nil, "Quiet", person(:alpha_manager).id ] ], seen.sort
  ensure
    Thread.current[:mcp_field_changes] = nil
  end

  test "a hook that fails leaves every value as it was" do
    Hook.create!(name: "Broken hook", event: "person_fields - value changed", code: "raise 'broken'")

    result = assert_unchanged(:admin, { "notes" => "Quiet", "nickname" => "Sam" })

    assert_equal "Internal error", result.error
    assert_nil stored(@notes)
    assert_nil stored(@self_field)
  end

  CONTACT_KEYS = %w[phone address birthday email].freeze

  def group_keys(result)
    result.value["groups"].flat_map { |group| group["fields"] }.map { |field| field["key"] }
  end

  test "a minor's result has no contact details, whoever asks" do
    @subject.update!(birthday: 10.years.ago.to_date, phone_number: "555-0100", address: "1 Main St")

    [ :admin, :alpha_manager ].each do |viewer|
      @subject.set_field_value(@notes, nil)
      result = update(viewer, { "notes" => "Quiet" })
      assert_nil result.error
      assert_empty group_keys(result) & CONTACT_KEYS, viewer.to_s
      assert_includes group_keys(result), "dietary_restrictions"
    end
  end

  test "an adult made a minor by the same call gets no contact details back" do
    built_in("phone_number").update!(read_permission: :everyone)
    @subject.update!(phone_number: "555-0100")

    result = update(:admin, { "notes" => "x", "birthday" => 5.years.ago.to_date.iso8601 })

    assert_nil result.error
    assert_empty group_keys(result) & CONTACT_KEYS
    assert_not_includes result.to_response.content.to_s, "555-0100"
  end

  test "a birthday outside what the database can store is refused without quoting it" do
    [ "5874898-01-01", "+9999999-01-01", "-4800-01-01" ].each do |value|
      result = assert_unchanged(:admin, { "birthday" => value })

      assert_equal "Birthday isn't a valid date", result.error
      assert_equal "error", result.outcome.to_s
      assert_equal ADULT, Person.find(@subject.id).birthday
    end
  end

  test "an ordinary birthday still works" do
    assert_nil update(:admin, { "birthday" => "1990-05-06" }).error
    assert_equal Date.new(1990, 5, 6), Person.find(@subject.id).birthday
  end
end
