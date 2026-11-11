require "test_helper"

class PeopleSearchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    PersonField.ensure_system_fields!

    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @viewer = create_member("viewer@example.com", "Vera", "Viewer")
    @peanut = create_member("peanut@example.com", "Pat", "Peanut", dietary_restrictions: "peanut allergy", birthday: Date.new(2015, 1, 2))
    @plain = create_member("plain@example.com", "Quinn", "Plain", dietary_restrictions: "none", birthday: Date.new(2010, 1, 2))

    sign_in @viewer.user
  end

  test "searching built-in details is unchanged after upgrading" do
    get people_path, params: { q: { dietary_restrictions_cont: "peanut" } }

    assert_response :success
    assert_includes response.body, "Peanut"
    assert_not_includes response.body, "Plain"
    assert_select "a", text: "Age"
  end

  test "a restricted detail can't be searched or sorted by non-admins" do
    restrict("dietary_restrictions")
    restrict("birthday")

    get people_path, params: { q: { dietary_restrictions_cont: "peanut" } }
    assert_includes response.body, "Peanut"
    assert_includes response.body, "Plain"

    get people_path, params: { q: { s: "birthday asc" } }
    assert_select "a", text: "Age", count: 0
  end

  test "admins can still search restricted details" do
    restrict("dietary_restrictions")
    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    sign_in admin

    get people_path, params: { q: { dietary_restrictions_cont: "peanut" } }

    assert_includes response.body, "Peanut"
    assert_not_includes response.body, "Plain"
  end

  test "searching through an association without a viewer fails closed" do
    restrict("dietary_restrictions")

    assert_not_includes Person.ransackable_attributes, "dietary_restrictions"
    assert_includes Person.ransackable_attributes, "phone_number"
    assert_equal 2, Membership.where(team: @team, person: [ @peanut, @plain ]).ransack(person_dietary_restrictions_cont: "peanut").result.count
  end

  test "membership search follows the birthday field" do
    assert_includes Membership.ransackable_attributes(@viewer.user), "person.birthday"

    restrict("birthday")

    assert_not_includes Membership.ransackable_attributes(@viewer.user), "person.birthday"
  end

  test "personal profile fields are filtered from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(person: {
      first_name: "Pat",
      address: "1 Main St",
      birthday: "2015-01-02",
      dietary_restrictions: "peanut allergy",
      phone_number: "555-0100",
      person_field_values: { food_allergies: "peanut" }
    })

    assert_equal "Pat", filtered[:person][:first_name]
    %i[address birthday dietary_restrictions phone_number person_field_values].each do |key|
      assert_equal "[FILTERED]", filtered[:person][key], "#{key} was not filtered"
    end
  end

  private

  def restrict(source)
    PersonField.find_by!(system_source: source).update!(read_permission: "family", write_permission: "self_and_leaders")
  end

  def create_member(email, first, last, **attributes)
    user = User.create!(email: email, password: "Password1!")
    person = Person.create!(user: user, first_name: first, last_name: last, **attributes)
    Membership.create!(person: person, team: @team, manager: false)
    person
  end
end
