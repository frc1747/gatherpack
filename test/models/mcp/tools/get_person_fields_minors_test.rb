require "test_helper"
require_relative "../../../support/mcp_world"

# A minor's contact details stay out of get_person_fields and get_person's
# "fields" key for every viewer, and everything else is unchanged.
class Mcp::Tools::GetPersonFieldsMinorsTest < ActiveSupport::TestCase
  include McpWorld

  BUILT_IN_KEYS = %w[email phone address birthday].freeze
  WITHHELD_VALUES = %w[alphamember@example.com 555-0100 555-0200 kid@example.net].freeze
  KEPT_NAMES = [ "Dietary Restrictions", "Shirt Size", "Gender", "Nickname", "Locker", "Allergies" ].freeze

  setup do
    build_mcp_world
    @restore_person_fields = apply_settings(feature_person_fields: "true")
    PersonField.ensure_system_fields!
    @subject = person(:alpha_member)
    @subject.update!(phone_number: "555-0100", address: "1 Main St", dietary_restrictions: "Peanuts", shirt_size: "M", gender: "F")

    @emergency_phone = custom_field("Emergency Phone", :phone, "555-0200")
    @other_email = custom_field("Other Email", :email, "kid@example.net")
    custom_field("Nickname", :string, "Sam")
    custom_field("Locker", :integer, 12)
    custom_field("Allergies", :text, "Nuts")

    @guardian = create_world_person("AlphaGuardian", @alpha)
    minor = RelationshipType.create!(parent_label: "Guardian of", child_label: "Ward of", permission: :added_by_admin, guardianship: :minor)
    Relationship.create!(parent: @guardian, child: @subject, relationship_type: minor, created_by: person(:admin))
  end

  teardown { @restore_person_fields&.call }

  def custom_field(name, type, value)
    PersonField.create!(name: name, data_type: type, read_permission: :everyone, write_permission: :admin).tap do |field|
      @subject.set_field_value(field, value)
    end
  end

  def viewers
    [ user(:admin), user(:alpha_manager), user(:ward), user(:alpha_member), @guardian.user ]
  end

  # The groups from each tool, for one viewer, with a label for messages.
  def each_result(viewer)
    subject_id = @subject.neat_id
    yield "get_person_fields as #{viewer.email}", call_tool("get_person_fields", user: viewer, person_id: subject_id).value["groups"]
    yield "get_person as #{viewer.email}", call_tool("get_person", user: viewer, person_id: subject_id).value["fields"]
  end

  def all_fields(groups)
    groups.flat_map { |group| group["fields"] }
  end

  def assert_withheld_for_every_viewer
    viewers.each do |viewer|
      each_result(viewer) do |label, groups|
        fields = all_fields(groups)
        assert_empty fields.map { |field| field["key"] } & (BUILT_IN_KEYS + [ @emergency_phone.key, @other_email.key ]), label
        assert_empty KEPT_NAMES - fields.map { |field| field["name"] }, label
        assert_empty WITHHELD_VALUES.select { |value| groups.to_json.include?(value) }, label
        assert_not_includes groups.to_json, "1 Main St", label
        assert_not_includes groups.to_json, @subject.birthday.iso8601, label if @subject.birthday
      end
    end
  end

  test "a 16-year-old's contact fields are left out for every viewer, and the rest remain" do
    @subject.update!(birthday: 16.years.ago.to_date)
    assert_withheld_for_every_viewer
  end

  test "someone with no birthday on file is treated as a minor" do
    @subject.update!(birthday: nil)
    assert_withheld_for_every_viewer
  end

  test "an adult is unchanged" do
    @subject.update!(birthday: Date.new(1990, 5, 6))
    expected = {
      "email" => "alphamember@example.com", "phone" => "555-0100", "address" => "1 Main St", "birthday" => "1990-05-06",
      @emergency_phone.key => "555-0200", @other_email.key => "kid@example.net", "nickname" => "Sam", "shirt_size" => "M"
    }
    viewers.each do |viewer|
      each_result(viewer) do |label, groups|
        values = all_fields(groups).to_h { |field| [ field["key"], field["value"] ] }
        assert_equal expected, values.slice(*expected.keys), label
      end
    end
  end

  test "a section with nothing left in it is left out" do
    names = ->(groups) { groups.map { |group| group["name"] } }
    @subject.update!(birthday: Date.new(1990, 5, 6))
    assert_includes names.call(call_tool("get_person_fields", user: user(:admin), person_id: @subject.neat_id).value["groups"]), "Contact"

    @subject.update!(birthday: 16.years.ago.to_date)
    groups = call_tool("get_person_fields", user: user(:admin), person_id: @subject.neat_id).value["groups"]
    assert_not_includes names.call(groups), "Contact"
    assert groups.all? { |group| group["fields"].any? }
  end

  test "the result gives no reason for what it leaves out" do
    @subject.update!(birthday: 16.years.ago.to_date)
    minor = call_tool("get_person_fields", user: user(:admin), person_id: @subject.neat_id).value
    assert_equal %w[groups person], minor.keys.sort
    assert_no_match(/minor|under 18|withheld/i, minor.to_json)
  end

  test "the tool's description states the rule generally" do
    assert_match(/under 18 or with no birthday on file/, Mcp::Tools::GetPersonFields.description)
  end

  test "a built-in field is matched on its source, whatever its key" do
    @subject.update!(birthday: 16.years.ago.to_date)
    phone = PersonField.find_by!(system_source: "phone_number")
    phone.update_column(:key, "mobile")
    groups = call_tool("get_person_fields", user: user(:admin), person_id: @subject.neat_id).value["groups"]
    assert_not_includes all_fields(groups).map { |field| field["key"] }, "mobile"
    assert_not_includes groups.to_json, "555-0100"
  end

  test "a custom field the type can't mark as a contact detail is still returned" do
    custom_field("Home Address", :string, "2 Side St")
    custom_field("Date of Birth", :date, Date.new(2010, 1, 2))
    @subject.update!(birthday: 16.years.ago.to_date)
    keys = all_fields(call_tool("get_person_fields", user: user(:admin), person_id: @subject.neat_id).value["groups"]).map { |field| field["key"] }
    assert_includes keys, "home_address"
    assert_includes keys, "date_of_birth"
  end
end
