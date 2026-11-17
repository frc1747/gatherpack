require "test_helper"

class UserSearchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
    sign_in @admin
  end

  test "user search results show the person's name" do
    get combo_search_path(q: "Ada", scope: "users", format: :turbo_stream)

    assert_response :success
    assert_includes response.body, %(data-filterable-as="Ada Admin")
  end

  test "a user without a person shows their email" do
    User.create!(email: "no-person@example.com", password: "Password1!")

    get combo_search_path(q: "no-person", scope: "users", format: :turbo_stream)

    assert_includes response.body, %(data-filterable-as="no-person@example.com")
  end

  test "a member's users search lists only their own login" do
    member = member_user
    sign_in member

    get combo_search_path(q: "", scope: "users", format: :turbo_stream)

    assert_response :success
    assert_includes response.body, %(data-filterable-as="Mia Member"), "a member doesn't find their own login"
    assert_not response.body.include?("Ada Admin"), "the users search lists someone else's login to a member"
  end

  test "a member's users search doesn't list a login from another team" do
    outsider = User.create!(email: "outsider@example.com", password: "Password1!")
    Person.create!(user: outsider, first_name: "Outsider", last_name: "World")
    sign_in member_user

    get combo_search_path(q: "Outsider", scope: "users", format: :turbo_stream)

    assert_not response.body.include?("Outsider World"), "the users search lists a login from another team to a member"
  end

  test "a member's users search says nothing about other logins' email addresses" do
    outsider = User.create!(email: "outsider@example.com", password: "Password1!")
    Person.create!(user: outsider, first_name: "Outsider", last_name: "World")
    sign_in member_user

    get combo_search_path(q: "outsider@", scope: "users", format: :turbo_stream)
    listed_for_hit = response.body.include?("Outsider World")
    get combo_search_path(q: "zzz@", scope: "users", format: :turbo_stream)
    listed_for_miss = response.body.include?("Outsider World")

    assert_equal listed_for_miss, listed_for_hit, "the users search answers whether a login's email contains a given string"
  end

  test "a member's users search doesn't show the email of a login without a person" do
    User.create!(email: "no-person@example.com", password: "Password1!")
    sign_in member_user

    get combo_search_path(q: "no-person", scope: "users", format: :turbo_stream)

    assert_not response.body.include?("no-person@example.com"), "the users search shows a member the email of a login with no person"
  end

  private

  def member_user
    user = User.create!(email: "member@example.com", password: "Password1!")
    person = Person.create!(user: user, first_name: "Mia", last_name: "Member", display_name: "Mia Member")
    Membership.create!(person: person, team: Team.create!(name: "Den", team_type: team_types(:one)))
    user
  end
end
