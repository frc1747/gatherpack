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

  test "the pages index doesn't list or excerpt a team's restricted pages to a member" do
    create_restricted_pages
    sign_in @member.user

    get pages_path

    assert_response :success
    assert listed?("Notes for all"), "the index doesn't list the team's own page"
    assert_not listed?("Leaders only"), "the index lists a manager-only page to a member"
    assert_not listed?("alarm code"), "the index prints the start of a manager-only page's content to a member"
    assert_not listed?("Admin runbook"), "the index lists an admin-only page to a member"
    assert_not listed?("hunter2"), "the index prints the start of an admin-only page's content to a member"
  end

  test "a team's pages tab doesn't list its restricted pages to a member" do
    create_restricted_pages
    sign_in @member.user

    get pages_team_path(@team)

    assert_response :success
    assert listed?("Notes for all"), "the pages tab doesn't list the team's own page"
    assert_not listed?("Leaders only"), "the pages tab lists a manager-only page to a member"
    assert_not listed?("Admin runbook"), "the pages tab lists an admin-only page to a member"
  end

  test "a content search on the pages index says nothing about restricted pages" do
    create_restricted_pages
    sign_in @member.user

    [ [ "Leaders only", "under the mat", "under the rug" ], [ "Admin runbook", "hunter2", "hunter3" ] ].each do |title, hit, miss|
      get pages_path, params: { q: { content_cont: hit } }
      listed_for_hit = response.body.include?(title)
      get pages_path, params: { q: { content_cont: miss } }
      listed_for_miss = response.body.include?(title)

      assert_equal listed_for_miss, listed_for_hit, "a content search answers whether #{title.inspect} contains #{hit.inspect}"
    end
  end

  test "managers of the team and of the teams above it list its manager-only pages" do
    create_restricted_pages
    child = Team.create!(name: "Den", team_type: team_types(:one), parent: @team)
    Page.create!(title: "Den leaders", content: "Den plans", viewer: "manager", editor: "manager", team: child)
    leader = create_user("leader@example.com").person
    Membership.create!(person: leader, team: @team, manager: true)
    sign_in leader.user

    get pages_path

    assert listed?("Leaders only"), "a manager doesn't see their team's manager-only page"
    assert listed?("Den leaders"), "a manager doesn't see a manager-only page of a team below theirs"
    assert_not listed?("Admin runbook"), "the index lists an admin-only page to a manager"
  end

  test "an admin lists every page" do
    create_restricted_pages
    sign_in create_user("admin@example.com", admin: true)

    get pages_path

    [ "Notes for all", "Leaders only", "Admin runbook" ].each { |title| assert listed?(title), "an admin doesn't see #{title.inspect}" }
  end

  private

  def listed?(text)
    response.body.include?(text)
  end

  def create_restricted_pages
    @member = create_user("member@example.com").person
    Membership.create!(person: @member, team: @team)
    Page.create!(title: "Notes for all", content: "Meeting at seven", viewer: "team", editor: "team", team: @team)
    Page.create!(title: "Leaders only", content: "Shop alarm code is 4321 and the spare key is under the mat.", viewer: "manager", editor: "manager", team: @team)
    Page.create!(title: "Admin runbook", content: "Wifi password hunter2", viewer: "admin", editor: "admin", team: @team)
  end

  def create_user(email, **flags)
    user = User.create!(email: email, password: "Password1!", **flags)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    user
  end
end
