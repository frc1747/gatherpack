require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @team = Team.create!(name: "Club", team_type: team_types(:one))
    @page = Page.create!(title: "Roster", content: "<%= 1 + 1 %>", dynamic: true, viewer: "team", editor: "admin", team: @team)
  end

  test "an admin who isn't an architect can't change a dynamic page's content" do
    sign_in create_user("admin@example.com", admin: true)

    patch page_path(@page), params: { page: { title: "Team roster", content: "<%= `id` %>" } }

    @page.reload
    assert_equal "Team roster", @page.title
    assert_equal "<%= 1 + 1 %>", @page.content
  end

  test "an admin who isn't an architect can't make a page dynamic" do
    page = Page.create!(title: "Notes", content: "Hello", viewer: "team", editor: "team", team: @team)
    sign_in create_user("admin@example.com", admin: true)

    patch page_path(page), params: { page: { content: "<%= `id` %>", dynamic: "1" } }

    page.reload
    assert_not page.dynamic
    assert_equal "<%= `id` %>", page.content
  end

  test "an architect changes a dynamic page's content" do
    sign_in create_user("architect@example.com", admin: true, architect: true)

    patch page_path(@page), params: { page: { content: "<%= 2 + 2 %>" } }

    assert_equal "<%= 2 + 2 %>", @page.reload.content
  end

  test "the edit form shows a dynamic page's content read-only to non-architects" do
    sign_in create_user("admin@example.com", admin: true)

    get edit_page_path(@page)

    assert_response :success
    assert_select "textarea[name=?]", "page[content]", count: 0
    assert_select "pre", text: "<%= 1 + 1 %>"
  end

  private

  def create_user(email, **flags)
    user = User.create!(email: email, password: "Password1!", **flags)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    user
  end
end
