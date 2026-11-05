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

  test "person fields' grant is registered by default" do
    assert_includes RelationshipType.guardian_grants, "see the child's profile and fields set to family or guardian levels, and edit them"
  end

  test "registering a grant twice doesn't duplicate it" do
    preserving_guardian_grants do
      original = RelationshipType.guardian_grants

      RelationshipType.register_guardian_grant("do something new")
      RelationshipType.register_guardian_grant("do something new")

      assert_equal original + [ "do something new" ], RelationshipType.guardian_grants
    end
  end

  test "a conditional grant is listed only while its condition holds" do
    preserving_guardian_grants do
      enabled = false
      RelationshipType.register_guardian_grant("do something new", if: -> { enabled })

      assert_not_includes RelationshipType.guardian_grants, "do something new"

      enabled = true

      assert_includes RelationshipType.guardian_grants, "do something new"
    end
  end

  test "the grants list can't be changed from outside the registry" do
    original = RelationshipType.guardian_grants

    RelationshipType.guardian_grants << "do something new"

    assert_equal original, RelationshipType.guardian_grants
  end

  test "changing a type asks for confirmation naming the relationship count" do
    type = relationship_types(:one)
    add_relationship(type)

    assert_equal "This makes the parent side of 2 relationships guardians.", type.guardianship_change_confirmation

    type.update!(guardianship: :minor)

    assert_equal "This stops the parent side of 2 relationships being guardians.", type.guardianship_change_confirmation
  end

  test "the confirmation reads correctly for one relationship" do
    type = relationship_types(:one)

    assert_equal "This makes the parent side of 1 relationship a guardian.", type.guardianship_change_confirmation

    type.update!(guardianship: :consented)

    assert_equal "This stops the parent side of 1 relationship being a guardian.", type.guardianship_change_confirmation
  end

  test "the confirmation follows the saved guardianship, not an unsaved change" do
    type = relationship_types(:one)

    type.guardianship = :minor

    assert_not type.guardianship_saved?
    assert_equal "This makes the parent side of 1 relationship a guardian.", type.guardianship_change_confirmation
  end

  test "a new type or a type with no relationships has no confirmation" do
    assert_nil RelationshipType.new.guardianship_change_confirmation

    type = RelationshipType.create!(parent_label: "Parent of", child_label: "Child of", permission: :added_by_admin)

    assert_nil type.guardianship_change_confirmation
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

  private

  def preserving_guardian_grants
    original = RelationshipType.instance_variable_get(:@guardian_grants).dup
    yield
  ensure
    RelationshipType.instance_variable_set(:@guardian_grants, original)
  end

  def add_relationship(type)
    Relationship.new(relationship_type: type, parent: people(:one), child: people(:two)).save!(validate: false)
  end
end
