require "test_helper"
require_relative "../../../support/mcp_world"

# update_person (task 70) takes a few base-profile attributes. This checks that none of
# the fields person fields withhold, built in or custom, can be reached through it.
class Mcp::Tools::UpdatePersonWithheldTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    @restore_person_fields = apply_settings(feature_person_fields: "true")
    PersonField.ensure_system_fields!
    @subject = person(:alpha_member)
    @subject.update!(birthday: 10.years.ago.to_date, phone_number: "555-0100", address: "1 Main St", dietary_restrictions: "None")
  end

  teardown { @restore_person_fields&.call }

  def update(viewer, **arguments)
    call_tool("update_person", user: user(viewer), person_id: @subject.neat_id, **arguments)
  end

  test "every built-in detail a minor has withheld is refused by name, for an admin too" do
    withheld = { phone_number: "555-0199", phone: "555-0199", address: "2 Elm St", birthday: "1980-01-01", dietary_restrictions: "Nuts", email: "kid@example.net" }
    original = Person.find(@subject.id).attributes.except("updated_at")

    withheld.each do |name, value|
      %i[admin alpha_manager alpha_member].each do |viewer|
        assert_no_difference -> { AuditLog.count } do
          result = update(viewer, name => value)
          assert result.error?, "#{viewer} #{name}"
          assert_not_equal "Internal error", result.error
          assert_nil result.changed
        end
      end
    end
    assert_equal original, Person.find(@subject.id).attributes.except("updated_at")
    assert_not_equal "kid@example.net", @subject.user.reload.email
  end

  test "the arguments it takes are none of the person fields' sources" do
    attributes = Mcp::Tools::UpdatePerson::PROFILE_ARGUMENTS
    sources = PersonField.system.pluck(:system_source).map { |source| source.delete_prefix("user.") }

    assert_empty attributes & sources
    assert_empty Mcp::Tools::UpdatePerson.argument_names & (sources - %w[email])
  end

  test "a custom field's key isn't an argument either" do
    PersonField.create!(name: "Emergency Phone", data_type: :phone, read_permission: :everyone, write_permission: :everyone)

    result = update(:admin, emergency_phone: "555-0123")

    assert result.error?
    assert_nil Person.find(@subject.id).field_value("emergency_phone")
  end

  test "the allowed attributes still work for a minor and leave the details alone" do
    assert_nil update(:admin, bio: "Hello").error
    assert_equal [ "Hello", "555-0100", "1 Main St" ], Person.find(@subject.id).then { |person| [ person.bio, person.phone_number, person.address ] }
  end
end
