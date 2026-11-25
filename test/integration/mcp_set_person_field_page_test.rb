require "test_helper"
require_relative "../support/mcp_world"

# set_person_field against the real edit page: the same input from the same
# viewer stores the same thing, or nothing on both sides.
class McpSetPersonFieldPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @restore_person_fields = apply_settings(feature_person_fields: "true")
    PersonField.ensure_system_fields!
    @subject = person(:alpha_member)
    @subject.update!(birthday: Date.new(1980, 1, 1), phone_number: "555-0100", address: "1 Main St")
    @guardian = create_world_person("AlphaGuardian", @alpha)
    minor = RelationshipType.create!(parent_label: "Guardian of", child_label: "Ward of", permission: :added_by_admin, guardianship: :minor)
    Relationship.create!(parent: @guardian, child: @subject, relationship_type: minor, created_by: person(:admin))
    @writer = create_world_person("BadgeWriter", @alpha)
    @writer_badge = create_world_badge("Field Writer")
    BadgeAssignment.create!(badge: @writer_badge, person: @writer)
    @viewers = [ user(:admin), user(:alpha_manager), user(:alpha_member), user(:ward), user(:beta_member), @guardian.user, @writer.user ]
  end

  teardown { @restore_person_fields&.call }

  def stored(field)
    Person.find(@subject.id).field_value(field)
  end

  # The other team's member can't reach this person on the page or in the tool.
  def expected_writers(field)
    (@viewers - [ user(:beta_member) ]).count { |viewer| field.writable_by?(viewer.person, @subject) }
  end

  # Tries the input from each viewer, on the page and then through the tool,
  # putting the original value back after each. Returns how many viewers wrote.
  def compare(field, form_value, tool_value, viewers: @viewers)
    original = stored(field)
    writes = 0
    viewers.each do |viewer|
      label = "#{viewer.email} on #{field.key}"

      sign_in viewer
      patch person_path(@subject), params: { person: { person_field_values: { field.key => form_value } } }
      sign_out viewer
      by_page = stored(field)
      Person.find(@subject.id).set_field_value(field, original)

      call_tool("set_person_field", user: viewer, person_id: @subject.neat_id, field_key: field.key, value: tool_value)
      by_tool = stored(field)
      Person.find(@subject.id).set_field_value(field, original)

      assert by_page == by_tool, "#{label}: page stored #{by_page.inspect}, tool stored #{by_tool.inspect}"
      writes += 1 if by_tool != original
    end
    writes
  end

  test "custom fields, at every write level" do
    AudienceLevels::PERMISSION_LEVELS.each_key do |level|
      field = PersonField.create!(name: "Level #{level}", data_type: :string, read_permission: :everyone, write_permission: level)
      expected = expected_writers(field)

      assert_operator expected, :>, 0, level
      assert_equal expected, compare(field, "Changed", "Changed"), level
    end
  end

  test "built-in fields, at the levels they ship with and tightened" do
    { "phone_number" => "555-0199", "address" => "2 Elm St", "birthday" => "1981-02-03", "dietary_restrictions" => "None" }.each do |source, value|
      field = PersonField.find_by!(system_source: source)
      [ field.write_permission, "leaders", "admin" ].uniq.each do |level|
        field.update!(read_permission: :everyone, write_permission: level)
        expected = expected_writers(field)

        assert_operator expected, :>, 0, "#{source} at #{level}"
        assert_equal expected, compare(field, value, value), "#{source} at #{level}"
      end
    end
  end

  test "typed values store the same as the form's" do
    admin = [ user(:admin) ]
    fields = {
      PersonField.create!(name: "Yes", data_type: :boolean, read_permission: :everyone, write_permission: :admin) => [ "1", true ],
      PersonField.create!(name: "Number", data_type: :integer, read_permission: :everyone, write_permission: :admin) => [ "7", 7 ],
      PersonField.create!(name: "Day", data_type: :date, read_permission: :everyone, write_permission: :admin) => [ "2026-05-01", "2026-05-01" ],
      PersonField.create!(name: "Size", data_type: :select, choices_text: "S\nM", read_permission: :everyone, write_permission: :admin) => [ "M", "M" ],
      PersonField.create!(name: "Many", data_type: :multi_select, choices_text: "A\nB", read_permission: :everyone, write_permission: :admin) => [ %w[A B], %w[A B] ],
      PersonField.create!(name: "Long", data_type: :text, read_permission: :everyone, write_permission: :admin) => [ "two\nlines", "two\nlines" ]
    }
    fields.each { |field, (form, tool)| assert_equal 1, compare(field, form, tool, viewers: admin), field.key }
  end

  test "a badge's write grant and a team's field" do
    granted = PersonField.create!(name: "Granted", data_type: :string, read_permission: :admin, write_permission: :admin)
    PersonFieldBadgeGrant.create!(person_field: granted, badge: @writer_badge, access: :write)
    assert_equal 2, compare(granted, "Changed", "Changed")

    elsewhere = PersonField.create!(name: "Elsewhere", data_type: :string, read_permission: :everyone, write_permission: :everyone, team: @beta)
    assert_equal 0, compare(elsewhere, "Changed", "Changed")
  end

  test "the value stays out of the request log, refused or not" do
    field = PersonField.create!(name: "Logged", data_type: :text, read_permission: :everyone, write_permission: :admin)
    [ user(:admin), user(:alpha_member) ].each do |viewer|
      token = mcp_token(viewer, scopes: "mcp_write")
      logged = nil
      subscriber = ->(*, payload) { logged = payload[:params].to_s if payload[:controller] == "McpController" }
      with_settings(mcp_write_enabled: "true") do
        ActiveSupport::Notifications.subscribed(subscriber, "process_action.action_controller") do
          mcp_post(token, "tools/call", { name: "set_person_field", arguments: { person_id: @subject.neat_id, field_key: field.key, value: "555-867-5309" } })
        end
      end

      assert_response :success
      assert_includes logged, @subject.neat_id
      assert_not_includes logged, "555-867-5309"
    end
    assert_equal "555-867-5309", stored(field)
  end
end
