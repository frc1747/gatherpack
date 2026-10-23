require "test_helper"

# Searches over people pass the signed-in user to Ransack, so searchable
# attributes can depend on who is searching.
class RansackAuthObjectTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Records the auth_object each ransackable_attributes call receives, while
  # a test is listening.
  module RecordAuthObject
    def ransackable_attributes(auth_object = nil)
      Thread.current[:ransack_auth_objects]&.<<(auth_object)
      super
    end
  end
  Person.singleton_class.prepend(RecordAuthObject)
  Membership.singleton_class.prepend(RecordAuthObject)

  setup do
    host! "localhost"
    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @user = User.create!(email: "viewer@example.com", password: "Password1!")
    person = Person.create!(user: @user, first_name: "Vera", last_name: "Viewer", birthday: Date.new(2015, 6, 15))
    Membership.create!(person: person, team: @team, manager: true)
    sign_in @user
    Thread.current[:ransack_auth_objects] = []
  end

  teardown do
    Thread.current[:ransack_auth_objects] = nil
  end

  test "the people directory" do
    get people_path, params: { q: { first_name_cont: "Ver" } }

    assert_auth_object_was_the_user
  end

  test "person search" do
    get combo_search_path(q: "Ver", scope: "people", format: :turbo_stream)

    assert_auth_object_was_the_user
  end

  test "team memberships" do
    get team_memberships_path(@team), params: { q: { "person.first_name_cont" => "Ver" }, people_q: { first_name_cont: "Ver" } }

    assert_auth_object_was_the_user
  end

  test "calendar birthdays" do
    get "/calendar/calendar.json", params: { birthdays: "1", start_time: "2026-01-01", end_time: "2026-12-31", q: { name_i_cont: "Ver" } }

    assert_auth_object_was_the_user
  end

  private

  def assert_auth_object_was_the_user
    recorded = Thread.current[:ransack_auth_objects]
    assert recorded.any?, "no ransack calls were recorded"
    assert recorded.all? { |auth_object| auth_object == @user }, "expected every call to pass the user, got #{recorded.map(&:class).uniq}"
  end
end
