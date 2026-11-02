require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::GetPersonFieldsTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    apply_person_fields_feature
    @section = PersonFieldGroup.create!(name: "Health")
    @everyone = PersonField.create!(name: "Nickname", data_type: :string, read_permission: :everyone, write_permission: :admin)
    @everyone.update!(person_field_group: @section)
    @teammates = PersonField.create!(name: "Locker", data_type: :integer, read_permission: :team, write_permission: :admin)
    @family = PersonField.create!(name: "Allergies", data_type: :text, read_permission: :family, write_permission: :admin)
    @leaders = PersonField.create!(name: "Notes", data_type: :text, read_permission: :leaders, write_permission: :admin)
    @admin_only = PersonField.create!(name: "Secret", data_type: :string, read_permission: :admin, write_permission: :admin)
    @hidden = PersonField.create!(name: "Hidden", data_type: :string, read_permission: :everyone, write_permission: :admin, show_on_profile: false)
    @subject = person(:alpha_member)
    {
      @everyone => "Sam", @teammates => 12, @family => "Peanuts", @leaders => "Quiet", @admin_only => "x", @hidden => "y"
    }.each { |field, value| @subject.set_field_value(field, value) }

    @guardian = create_world_person("AlphaGuardian", @alpha)
    minor = RelationshipType.create!(parent_label: "Guardian of", child_label: "Ward of", permission: :added_by_admin, guardianship: :minor)
    Relationship.create!(parent: @guardian, child: @subject, relationship_type: minor, created_by: person(:admin))
    @reviewer = create_world_person("Reviewer", @alpha)
    @reviewer_badge = create_world_badge("Field Reader")
    BadgeAssignment.create!(badge: @reviewer_badge, person: @reviewer)
    PersonFieldBadgeGrant.create!(person_field: @admin_only, badge: @reviewer_badge, access: :read)
  end

  teardown { @restore_person_fields&.call }

  def apply_person_fields_feature
    @restore_person_fields = apply_settings(feature_person_fields: "true")
  end

  def fields(viewer, target = :alpha_member)
    result = call_tool("get_person_fields", user: viewer.is_a?(Symbol) ? user(viewer) : viewer.user, person_id: person(target).neat_id)
    assert_not result.error?, result.error
    result.value["groups"].flat_map { |group| group["fields"] }.map { |field| field["name"] }
  end

  test "an admin sees every field shown on the profile, grouped with type and value" do
    value = call_tool("get_person_fields", user: user(:admin), person_id: @subject.neat_id).value

    assert_equal({ "id" => @subject.neat_id, "name" => "AlphaMember World" }, value["person"])
    health = value["groups"].find { |group| group["name"] == "Health" }
    assert_equal [ { "key" => "nickname", "name" => "Nickname", "type" => "string", "value" => "Sam" } ], health["fields"]
    all = value["groups"].flat_map { |group| group["fields"] }
    assert_includes all, { "key" => "locker", "name" => "Locker", "type" => "integer", "value" => 12 }
    assert_includes all.map { |field| field["name"] }, "Secret"
    assert_not_includes all.map { |field| field["name"] }, "Hidden"
  end

  test "a team manager reads fields up to leaders level" do
    assert_equal [ "Allergies", "Locker", "Nickname", "Notes" ], fields(:alpha_manager).sort
    assert_not_includes fields(:alpha_manager), "Secret"
  end

  test "a teammate reads everyone and team fields only" do
    names = fields(:ward)
    assert_includes names, "Nickname"
    assert_includes names, "Locker"
    assert_not_includes names, "Allergies"
    assert_not_includes names, "Notes"
    assert_not_includes names, "Secret"
  end

  test "the subject sees their own team, family and everyone fields but not leaders-only ones" do
    names = fields(:alpha_member)
    assert_includes names, "Allergies"
    assert_not_includes names, "Notes"
  end

  test "a guardian of the subject reads family fields" do
    names = fields(@guardian)
    assert_includes names, "Allergies"
    assert_not_includes names, "Secret"
  end

  test "a badge grant lets its holder read the field" do
    assert_includes fields(@reviewer), "Secret"
    assert_not_includes fields(:ward), "Secret"
  end

  test "a member on another team can't find the person" do
    result = call_tool("get_person_fields", user: user(:beta_member), person_id: @subject.neat_id)
    assert_equal "Not found", result.error
  end

  test "an unrelated viewer who can see the person only gets the fields everyone can read" do
    Membership.create!(person: person(:beta_member), team: @alpha)
    names = fields(:beta_member)
    assert_includes names, "Nickname"
    assert_includes names, "Locker"
    assert_not_includes names, "Allergies"
  end

  test "self, self and leaders and guardians levels reach the right viewers" do
    only_self = PersonField.create!(name: "Mine", data_type: :string, read_permission: :self, write_permission: :admin)
    self_leaders = PersonField.create!(name: "Mine and leaders", data_type: :string, read_permission: :self_and_leaders, write_permission: :admin)
    guardians = PersonField.create!(name: "For guardians", data_type: :string, read_permission: :guardians, write_permission: :admin)
    [ only_self, self_leaders, guardians ].each { |field| @subject.set_field_value(field, "v") }

    assert_equal [ "Mine", "Mine and leaders" ], fields(:alpha_member).grep(/Mine/).sort
    assert_equal [ "Mine and leaders" ], fields(:alpha_manager).grep(/Mine/)
    assert_empty fields(:ward).grep(/Mine|guardians/)
    assert_includes fields(@guardian), "For guardians"
    assert_not_includes fields(:alpha_member), "For guardians"
    assert_includes fields(:alpha_manager), "For guardians"
    assert_empty fields(@guardian).grep(/Mine/)
  end

  test "a guardian on no shared team reads guardian fields; an expired guardianship is Not found" do
    family = PersonField.create!(name: "Family only", data_type: :string, read_permission: :family, write_permission: :admin)
    kid = create_world_person("Kid", @alpha)
    kid.update!(birthday: Date.current - 10.years)
    kid.set_field_value(family, "v")
    lone = create_world_person("LoneGuardian")
    minor = RelationshipType.create!(parent_label: "Minor guardian of", child_label: "Minor ward of", permission: :added_by_admin, guardianship: :minor)
    Relationship.create!(parent: lone, child: kid, relationship_type: minor, created_by: person(:admin))

    result = call_tool("get_person_fields", user: lone.user, person_id: kid.neat_id)
    assert_includes result.value["groups"].flat_map { |group| group["fields"] }.map { |f| f["name"] }, "Family only"

    with_settings(guardianship_age_limit: "5") do
      assert_equal "Not found", call_tool("get_person_fields", user: lone.user, person_id: kid.neat_id).error
    end
  end

  test "built-in fields are returned with their value, a restricted one only to those who may read it" do
    PersonField.ensure_system_fields!
    @subject.update!(phone_number: "555-0100", birthday: Date.new(1990, 5, 6))
    PersonField.find_by!(system_source: "phone_number").update!(read_permission: :self_and_leaders)
    find = ->(viewer, key) { call_tool("get_person_fields", user: user(viewer), person_id: @subject.neat_id).value["groups"].flat_map { |g| g["fields"] }.find { |f| f["key"] == key } }

    assert_equal({ "key" => "phone", "name" => "Phone", "type" => "phone", "value" => "555-0100" }, find.call(:alpha_manager, "phone"))
    assert_nil find.call(:ward, "phone")
    assert_equal "1990-05-06", find.call(:ward, "birthday")["value"]
    assert_equal "alphamember@example.com", find.call(:ward, "email")["value"]
  end

  test "an empty string is null" do
    PersonField.ensure_system_fields!
    @subject.update_column(:dietary_restrictions, "")
    value = call_tool("get_person_fields", user: user(:admin), person_id: @subject.neat_id).value
    assert_nil value["groups"].flat_map { |g| g["fields"] }.find { |f| f["key"] == "dietary_restrictions" }["value"]
  end

  test "an empty field is null and a multi select is a list" do
    choice = PersonField.create!(name: "Tags", data_type: :multi_select, choices: %w[a b], read_permission: :everyone, write_permission: :admin)
    @subject.set_field_value(choice, %w[a b])
    other = person(:ward)
    value = call_tool("get_person_fields", user: user(:admin), person_id: other.neat_id).value
    all = value["groups"].flat_map { |group| group["fields"] }
    assert_nil all.find { |field| field["name"] == "Nickname" }["value"]
    empty = PersonField.create!(name: "Empty tags", data_type: :multi_select, choices: %w[a b], read_permission: :everyone, write_permission: :admin)
    @subject.set_field_value(empty, [])
    assert_nil call_tool("get_person_fields", user: user(:admin), person_id: @subject.neat_id).value["groups"].flat_map { |g| g["fields"] }.find { |f| f["name"] == "Empty tags" }["value"]
    assert_equal [ "a", "b" ], call_tool("get_person_fields", user: user(:admin), person_id: @subject.neat_id).value["groups"].flat_map { |group| group["fields"] }.find { |field| field["name"] == "Tags" }["value"]
  end

  test "get_person includes the same groups as fields while the feature is on" do
    viewer = user(:ward)
    direct = call_tool("get_person_fields", user: viewer, person_id: @subject.neat_id).value["groups"]
    assert_equal direct, call_tool("get_person", user: viewer, person_id: @subject.neat_id).value["fields"]
  end

  test "with the feature off the tool is neither listed nor callable and get_person has no fields key" do
    with_feature(:person_fields, false) do
      context = mcp_context(user(:admin))
      assert_not_includes Mcp.available_tools(context).map(&:tool_name), "get_person_fields"
      result = Mcp.tool("get_person_fields").run(context, { "person_id" => @subject.neat_id })
      assert_equal "Feature off", result.error
      assert_not call_tool("get_person", user: user(:admin), person_id: @subject.neat_id).value.key?("fields")
    end
  end
end
