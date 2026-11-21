require "test_helper"
require_relative "../support/settings_test_helper"

class RelationshipTest < ActiveSupport::TestCase
  include SettingsTestHelper

  setup do
    @admin = create_person("Ada", "Admin", admin: true)
    @parent = create_person("Pam", "Parent")
    @child = create_person("Cal", "Child", birthday: 10.years.ago.to_date)
    @sibling = create_person("Sid", "Sibling")

    @parent_of = RelationshipType.create!(parent_label: "Parent of", child_label: "Child of", permission: :added_by_admin, guardianship: :minor)
    @sibling_of = RelationshipType.create!(parent_label: "Sibling of", child_label: "Sibling of", permission: :added_by_user, guardianship: :none)
    @contact_of = RelationshipType.create!(parent_label: "Authorized contact of", child_label: "Has authorized contact", permission: :added_by_user, guardianship: :consented)
  end

  test "a relationship of a non-guardianship type grants nothing in either direction" do
    relate(@sibling, @child, @sibling_of)

    assert_empty @child.guardians
    assert_empty @sibling.guardians
    assert_empty @sibling.wards
  end

  test "a minor guardianship runs from the parent side to the child side only" do
    relate(@parent, @child, @parent_of)

    assert_equal [ @parent ], @child.guardians.to_a
    assert_equal [ @child ], @parent.wards.to_a
    assert_empty @parent.guardians
    assert_empty @child.wards
  end

  test "the parent side can't create a consented relationship" do
    relationship = Relationship.new(parent: @parent, child: @child, relationship_type: @contact_of, created_by: @parent)

    assert_not relationship.valid?
    assert_empty @child.guardians
  end

  test "the child side or an admin can create a consented relationship" do
    assert Relationship.new(parent: @parent, child: @child, relationship_type: @contact_of, created_by: @child).valid?
    assert Relationship.new(parent: @parent, child: @child, relationship_type: @contact_of, created_by: @admin).valid?
  end

  test "either side can delete a consented relationship" do
    relationship = relate(@parent, @child, @contact_of, created_by: @child)

    assert RelationshipPolicy.new(@child.user, relationship).destroy?
    assert RelationshipPolicy.new(@parent.user, relationship).destroy?
    assert_not RelationshipPolicy.new(@sibling.user, relationship).destroy?
  end

  test "only managers and admins can delete a minor guardianship" do
    team = Team.create!(name: "Den A", team_type: team_types(:one))
    Membership.create!(person: @child, team: team)
    leader = create_person("Lee", "Leader")
    Membership.create!(person: leader, team: team, manager: true)
    relationship = relate(@parent, @child, @parent_of)

    assert_not RelationshipPolicy.new(@child.user, relationship).destroy?
    assert_not RelationshipPolicy.new(@parent.user, relationship).destroy?
    assert_not RelationshipPolicy.new(@child.user, relationship).reverse?
    assert RelationshipPolicy.new(leader.user, relationship).destroy?
    assert RelationshipPolicy.new(@admin.user, relationship).destroy?
  end

  test "either side can still delete an ordinary relationship" do
    relationship = relate(@sibling, @child, @sibling_of)

    assert RelationshipPolicy.new(@child.user, relationship).destroy?
    assert RelationshipPolicy.new(@sibling.user, relationship).destroy?
    assert_not RelationshipPolicy.new(@parent.user, relationship).destroy?
  end

  test "with no age limit, guardianship of an adult continues" do
    @child.update!(birthday: 30.years.ago.to_date)
    relate(@parent, @child, @parent_of)

    with_settings(guardianship_age_limit: "") do
      assert_equal [ @parent ], @child.guardians.to_a
      assert_not @child.guardianship_expired?
      assert_nil @child.guardianship_ends_on
    end
  end

  test "with an age limit, minor guardianship ends on the birthday that reaches it" do
    relate(@parent, @child, @parent_of)

    with_settings(guardianship_age_limit: "18") do
      @child.update!(birthday: 18.years.ago.to_date + 1.day)
      assert_equal [ @parent ], @child.guardians.to_a
      assert_not @child.guardianship_expired?
      assert_equal Date.current + 1.day, @child.guardianship_ends_on

      @child.update!(birthday: 18.years.ago.to_date)
      assert_empty @child.guardians
      assert @child.guardianship_expired?
    end
  end

  test "missing birthdays follow the without-birthday setting" do
    @child.update!(birthday: nil)
    relate(@parent, @child, @parent_of)

    with_settings(guardianship_age_limit: "18", guardianship_ends_without_birthday: "false") do
      assert_equal [ @parent ], @child.guardians.to_a
      assert_not @child.guardianship_expired?
    end

    with_settings(guardianship_age_limit: "18", guardianship_ends_without_birthday: "true") do
      assert_empty @child.guardians
      assert @child.guardianship_expired?
    end
  end

  test "consented guardianship ignores the age limit" do
    @child.update!(birthday: 30.years.ago.to_date)
    relate(@parent, @child, @contact_of, created_by: @child)

    with_settings(guardianship_age_limit: "18") do
      assert_equal [ @parent ], @child.guardians.to_a
    end
  end

  test "guardians and wards agree with active_guardianships" do
    relate(@parent, @child, @parent_of)
    relate(@sibling, @child, @sibling_of)
    relate(@child, @sibling, @contact_of, created_by: @sibling)

    pairs = Relationship.active_guardianships.pluck(:parent_id, :child_id).sort
    from_people = [ @admin, @parent, @child, @sibling ].flat_map { |person| person.wards.map { |ward| [ person.id, ward.id ] } }.sort

    assert_equal pairs, from_people
    assert_equal [ @parent.id ], @child.guardians.pluck(:id)
    assert_equal [ @child.id ], @sibling.guardians.pluck(:id)
  end

  private

  def create_person(first, last, admin: false, **attributes)
    user = User.create!(email: "#{first.downcase}@example.com", password: "Password1!", admin: admin)
    Person.create!(user: user, first_name: first, last_name: last, **attributes)
  end

  def relate(parent, child, type, created_by: @admin)
    Relationship.create!(parent: parent, child: child, relationship_type: type, created_by: created_by)
  end
end
