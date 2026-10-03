require "test_helper"

class PeopleSearchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @viewer = create_member("viewer@example.com", "Vera", "Viewer")
    @peanut = create_member("peanut@example.com", "Pat", "Peanut", dietary_restrictions: "peanut allergy")
    @plain = create_member("plain@example.com", "Quinn", "Plain", dietary_restrictions: "none")

    sign_in @viewer.user
  end

  test "people search on profile attributes is unchanged" do
    get people_path, params: { q: { dietary_restrictions_cont: "peanut" } }

    assert_response :success
    assert_includes response.body, "Peanut"
    assert_not_includes response.body, "Plain"
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

  def create_member(email, first, last, **attributes)
    user = User.create!(email: email, password: "Password1!")
    person = Person.create!(user: user, first_name: first, last_name: last, **attributes)
    Membership.create!(person: person, team: @team, manager: false)
    person
  end
end
