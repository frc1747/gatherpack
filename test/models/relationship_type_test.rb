require "test_helper"

class RelationshipTypeTest < ActiveSupport::TestCase
  test "existing types confer no guardianship" do
    assert RelationshipType.all.all?(&:guardianship_none?)
    assert_not RelationshipType.guardianship_configured?
  end

  test "minor guardianship requires an admin or manager permission" do
    type = RelationshipType.new(parent_label: "Parent of", child_label: "Child of", guardianship: :minor)

    %w[added_by_team_member added_by_participant added_by_user].each do |permission|
      type.permission = permission
      assert_not type.valid?, "#{permission} should be rejected"
      assert_includes type.errors[:guardianship], "can only be set on types added by admins or managers"
    end

    %w[added_by_admin added_by_manager].each do |permission|
      type.permission = permission
      assert type.valid?, "#{permission} should be allowed"
    end
  end

  test "consented guardianship allows any permission" do
    type = RelationshipType.new(parent_label: "Contact of", child_label: "Has contact", guardianship: :consented, permission: :added_by_user)

    assert type.valid?
  end

  test "guardianship_configured? is true once a type grants guardianship" do
    RelationshipType.create!(parent_label: "Parent of", child_label: "Child of", guardianship: :minor, permission: :added_by_admin)

    assert RelationshipType.guardianship_configured?
  end

  test "relationship type changes fire hooks" do
    assert_includes Hook.catalog, "relationship_types - update"
    Hook.create!(name: "Record", event: "relationship_types - update", code: "Thread.current[:hooked_relationship_type] = model.guardianship")
    type = relationship_types(:one)

    type.update!(guardianship: :minor)

    assert_equal "minor", Thread.current[:hooked_relationship_type]
  ensure
    Thread.current[:hooked_relationship_type] = nil
  end
end
