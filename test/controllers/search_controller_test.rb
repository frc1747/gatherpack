require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
    sign_in @admin
  end

  def create_announcement(title:, content:)
    Announcement.create!(title: title, content: content, start_time: 1.day.ago, end_time: 1.day.from_now)
  end

  test "announcement search finds a title" do
    create_announcement(title: "Concessions shifts", content: "Pick a slot.")

    get combo_search_path(q: "concessions", scope: "announcements", format: :turbo_stream)

    assert_includes response.body, "Concessions shifts"
  end

  test "announcement search ignores link targets" do
    create_announcement(title: "Schedule", content: "See [the plan](https://example.com/concessions)")

    get combo_search_path(q: "concessions", scope: "announcements", format: :turbo_stream)

    assert_not_includes response.body, "Schedule"
  end
end
