require "test_helper"

class RelationshipsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    team = Team.create!(name: "Den", team_type: team_types(:one))
    @member = create_person("member@example.com", "Mia", "Member")
    Membership.create!(person: @member, team: team)
    @teammate = create_person("teammate@example.com", "Tess", "Teammate")
    Membership.create!(person: @teammate, team: team)
    @outsider = create_person("outsider@example.com", "Outsider", "World")
    Membership.create!(person: @outsider, team: Team.create!(name: "Elsewhere", team_type: team_types(:one)))
  end

  test "a member opens the new relationship form for themselves and a teammate" do
    sign_in @member.user

    [ @member, @teammate ].each do |person|
      get new_person_relationship_path(person)

      assert_response :success
      assert_includes response.body, person.display_name
    end
  end

  test "a member can't open the new relationship form for someone they can't see" do
    sign_in @member.user

    get new_person_relationship_path(@outsider)

    assert_not response.body.include?(@outsider.display_name), "relationships#new shows the name of a person the member can't see"
    assert_response :not_found
  end

  test "a member can't start a relationship for someone they can't see" do
    sign_in @member.user

    assert_no_difference "Relationship.count" do
      post person_relationships_path(@outsider), params: { relationship: { start_node: "#{relationship_types(:one).id}:p" } }
    end

    assert_not response.body.include?(@outsider.display_name), "relationships#create shows the name of a person the member can't see"
    assert_response :not_found
  end

  test "a member relates themselves to a teammate" do
    type = RelationshipType.create!(parent_label: "Mentor", child_label: "Mentee", permission: :added_by_user)
    sign_in @member.user

    assert_difference "Relationship.count", 1 do
      post person_relationships_path(@member), params: { relationship: { start_node: "#{type.id}:c", parent_id: @teammate.id } }
    end

    assert_redirected_to person_path(@member)
  end

  test "a member can't relate themselves to someone they can't see" do
    type = RelationshipType.create!(parent_label: "Mentor", child_label: "Mentee", permission: :added_by_user)
    sign_in @member.user

    post person_relationships_path(@member), params: { relationship: { start_node: "#{type.id}:c", parent_id: @outsider.id } }
    saved = Relationship.exists?(parent: @outsider, child: @member)
    get relationships_person_path(@member)

    assert_not response.body.include?(@outsider.display_name), "a member's relationships page shows the name of a person they can't see"
    assert_not saved, "relationships#create relates a member to a person they can't see"
  end

  private

  def create_person(email, first_name, last_name)
    user = User.create!(email: email, password: "Password1!")
    Person.create!(user: user, first_name: first_name, last_name: last_name, display_name: "#{first_name} #{last_name}")
  end
end
