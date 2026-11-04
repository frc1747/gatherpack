require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListPersonFieldsTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    @restore_person_fields = apply_settings(feature_person_fields: "true")
    PersonField.ensure_system_fields!
    @section = PersonFieldGroup.create!(name: "Health")
    @everyone = PersonField.create!(name: "Nickname", data_type: :string, read_permission: :everyone, write_permission: :admin, person_field_group: @section)
    @leaders = PersonField.create!(name: "Notes", data_type: :text, read_permission: :leaders, write_permission: :leaders, required: true)
    @admin_only = PersonField.create!(name: "Secret", data_type: :string, read_permission: :admin, write_permission: :admin)
    @size = PersonField.create!(name: "Jacket", data_type: :select, choices_text: "S\nM\nL", read_permission: :everyone, write_permission: :self)
    @locker = PersonField.create!(name: "Locker", data_type: :integer, min: "1", max: "40", read_permission: :everyone, write_permission: :self)
    @beta_only = PersonField.create!(name: "Beta Only", data_type: :string, read_permission: :everyone, write_permission: :everyone, team: @beta)
    @archived = PersonField.create!(name: "Old", data_type: :string, read_permission: :everyone, write_permission: :everyone, archived_at: Time.current)
  end

  teardown { @restore_person_fields&.call }

  def list(viewer)
    result = call_tool("list_person_fields", user: user(viewer))
    assert_nil result.error
    result.value["fields"].index_by { |field| field["key"] }
  end

  test "an admin gets every active field with its type, choices, range and required mark" do
    fields = list(:admin)

    assert_equal({ "key" => "nickname", "name" => "Nickname", "group" => "Health", "type" => "string", "choices" => nil,
                   "min" => nil, "max" => nil, "required" => false, "writable" => true }, fields["nickname"])
    assert_equal %w[S M L], fields["jacket"]["choices"]
    assert_equal [ "1", "40" ], fields["locker"].values_at("min", "max")
    assert_equal true, fields["notes"]["required"]
    assert_nil fields["notes"]["group"]
    assert_includes fields.keys, "secret"
    assert_includes fields.keys, "beta_only"
    assert_not_includes fields.keys, "old"
  end

  test "the built-in fields are listed, and the account email is never writable" do
    fields = list(:admin)

    assert_equal %w[email phone address birthday dietary_restrictions shirt_size gender].sort, (fields.keys & %w[email phone address birthday dietary_restrictions shirt_size gender]).sort
    assert_equal false, fields["email"]["writable"]
    assert_equal true, fields["phone"]["writable"]
    assert_equal "Contact", fields["phone"]["group"]
  end

  test "anyone else gets the fields they can see on someone's profile, and whether they can write them" do
    manager = list(:alpha_manager)
    assert_includes manager.keys, "nickname"
    assert_includes manager.keys, "notes"
    assert_not_includes manager.keys, "secret"
    assert_equal false, manager["nickname"]["writable"]
    assert_equal true, manager["notes"]["writable"]
    assert_equal true, manager["jacket"]["writable"]

    member = list(:alpha_member)
    assert_not_includes member.keys, "notes"
    assert_not_includes member.keys, "secret"
    assert_equal true, member["jacket"]["writable"]
    assert_equal false, member["nickname"]["writable"]
  end

  test "a field of another team is left out, and a badge with read access shows an admin-only field" do
    assert_not_includes list(:alpha_member).keys, "beta_only"
    assert_includes list(:beta_member).keys, "beta_only"

    PersonFieldBadgeGrant.create!(person_field: @admin_only, badge: @access_badge, access: :read)
    secret = list(:badge_holder)["secret"]
    assert_equal false, secret["writable"]
    PersonFieldBadgeGrant.find_by!(person_field: @admin_only).update!(access: :write)
    assert_equal true, list(:badge_holder)["secret"]["writable"]
  end

  test "the permission levels and badge grants are not given" do
    assert_equal %w[choices group key max min name required type writable], list(:alpha_manager)["nickname"].keys.sort
  end

  test "archived fields are left out, and custom fields while the feature is off" do
    with_feature(:person_fields, false) { assert_equal "Feature off", call_tool("list_person_fields", user: user(:admin)).error }

    @restore_person_fields.call
    @restore_person_fields = apply_settings(feature_person_fields: "true")
    assert_not_includes list(:admin).keys, "old"
  end

  test "a read token is enough, and it isn't a write" do
    assert_nil call_tool("list_person_fields", user: user(:admin), scopes: "mcp_read").error
    assert_not Mcp.tool("list_person_fields").write?
  end

  test "it writes nothing" do
    assert_no_difference -> { AuditLog.count } do
      call_tool("list_person_fields", user: user(:admin))
    end
  end

  test "a field no page shows the viewer is left out, even if they could read it" do
    relationship = RelationshipType.create!(parent_label: "Guardian of", child_label: "Ward of", permission: :added_by_admin, guardianship: :minor)
    Relationship.create!(parent: person(:guardian), child: person(:ward), relationship_type: relationship, created_by: person(:admin))
    PersonField.create!(name: "Custody Note", data_type: :select, choices_text: "Sole\nJoint", read_permission: :guardians,
      write_permission: :admin, show_on_profile: false)
    shown = PersonField.create!(name: "Pickup Note", data_type: :text, read_permission: :guardians, write_permission: :admin)

    guardian = list(:guardian)
    assert_not_includes guardian.keys, "custody_note"
    assert_includes guardian.keys, shown.key
    assert_includes list(:admin).keys, "custody_note"
  end

  test "a hidden field the viewer can write is still listed" do
    PersonField.create!(name: "Hidden Mine", data_type: :string, read_permission: :everyone, write_permission: :self, show_on_profile: false)

    assert_equal true, list(:alpha_member)["hidden_mine"]["writable"]
  end

  test "an admin sees a field of a team that has no members yet" do
    empty = Team.create!(name: "Empty", team_type: team_types(:one))
    PersonField.create!(name: "Empty Team Field", data_type: :string, read_permission: :everyone, write_permission: :admin, team: empty)

    assert_equal true, list(:admin)["empty_team_field"]["writable"]
    assert_not_includes list(:alpha_manager).keys, "empty_team_field"
  end

  test "writable counts only people the viewer can see" do
    field = PersonField.create!(name: "Beta Write", data_type: :string, read_permission: :admin, write_permission: :admin, team: @beta)
    PersonFieldBadgeGrant.create!(person_field: field, badge: @access_badge, access: :write)
    holder = create_world_person("AlphaHolder", @alpha)
    BadgeAssignment.create!(badge: @access_badge, person: holder)

    assert_not_includes list(:alpha_member).keys, "beta_write"
    assert_equal true, list(:badge_holder)["beta_write"]["writable"]
    assert_not_includes call_tool("list_person_fields", user: holder.user).value["fields"].map { |f| f["key"] }, "beta_write"
  end
end
