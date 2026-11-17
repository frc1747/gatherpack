require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    # Pack
    # ├── Den A: @student
    # └── Den B (requires approval): @zelda, @den_b_leader (manager)
    @pack = Team.create!(name: "Pack", team_type: team_types(:one))
    @den_a = Team.create!(name: "Den A", team_type: team_types(:one), parent: @pack)
    @den_b = Team.create!(name: "Den B", team_type: team_types(:one), parent: @pack, join_permission: :requires_approval)
    @student = create_person("student", "Sam", @den_a)
    @zelda = create_person("zelda", "Zelda", @den_b)
    @den_b_leader = create_person("den-b-leader", "Lee", @den_b, manager: true)
    @admin = create_person("admin", "Ada", @den_a, admin: true)
    Hook.create!(name: "Sync roster", event: "people - update", code: "API_KEY = 'sk_live_ABC'; post(model)")
  end

  test "a member can't list the people of a team whose roster they may not see" do
    sign_in @student.user

    get combo_search_path(q: "Zel", scope: "team_people:#{@den_b.id}", format: :turbo_stream)
    assert_not_includes response.body, @zelda.display_name
    get combo_search_path(q: "Zel", scope: "team_people:#{@den_b.neat_id}", format: :turbo_stream)
    assert_not_includes response.body, @zelda.display_name
    get search_path(q: "Zel", scope: "team_people:#{@den_b.id}")
    assert_not_includes css_select("#global-search-results").text, @zelda.display_name

    # The same member finds her by name where they may see her.
    get combo_search_path(q: "Zel", scope: "people", format: :turbo_stream)
    assert_includes response.body, @zelda.display_name
  end

  test "a member of a sub-team finds only themself among the people of the team above it" do
    sign_in @student.user

    get combo_search_path(q: "Test", scope: "team_people:#{@pack.id}", format: :turbo_stream)

    assert_includes response.body, @student.display_name
    assert_not_includes response.body, @zelda.display_name
    assert_not_includes response.body, @den_b_leader.display_name
  end

  test "a member gets no one from a team they're not on and may not list" do
    sign_in @student.user

    get combo_search_path(q: "Test", scope: "team_people:#{@den_b.id}", format: :turbo_stream)

    assert_not_includes response.body, @zelda.display_name
    assert_not_includes response.body, @den_b_leader.display_name
    assert_not_includes response.body, @student.display_name
  end

  test "the team's managers and admins list its people" do
    [ @den_b_leader, @admin ].each do |viewer|
      sign_in viewer.user

      get combo_search_path(q: "Zel", scope: "team_people:#{@den_b.id}", format: :turbo_stream)
      assert_includes response.body, @zelda.display_name, "#{viewer.first_name} didn't get the picker results"
      get search_path(q: "Zel", scope: "team_people:#{@den_b.id}")
      assert_includes css_select("#global-search-results").text, @zelda.display_name, "#{viewer.first_name} didn't get the search results"
    end
  end

  test "a team badge's assignment form offers the team's people to its manager" do
    badge = Badge.create!(name: "Den B star", short: "DB", color: "#336699", badge_type: badge_types(:one), team: @den_b, permission: :added_by_manager)
    sign_in @den_b_leader.user

    get new_badge_badge_assignment_path(badge)
    assert_response :success
    assert_includes response.body, ERB::Util.html_escape(combo_search_path(scope: "team_people:#{@den_b.id}", attribute: :person_id))

    get combo_search_path(q: "Zel", scope: "team_people:#{@den_b.id}", format: :turbo_stream)
    assert_includes response.body, @zelda.display_name
  end

  test "a member's global search doesn't show hooks or their code" do
    sign_in create_user("hook-member@example.com")

    get search_path, params: { q: "Sync" }

    assert_response :success
    assert_not response.body.include?("sk_live_ABC"), "the global search shows a hook's code to a member"
    assert_not response.body.include?("Sync roster"), "the global search lists a hook to a member"
  end

  test "a member's hooks picker doesn't list hooks" do
    sign_in create_user("hook-member@example.com")

    get combo_search_path(format: :turbo_stream), params: { q: "Sync", scope: "hooks" }

    assert_response :success
    assert_not response.body.include?("Sync roster"), "search/combo?scope=hooks lists a hook to a member"
  end

  test "an admin finds hooks in the global search and the picker" do
    sign_in create_user("hook-admin@example.com", admin: true)

    get search_path, params: { q: "Sync" }
    assert_includes response.body, "Sync roster"

    get combo_search_path(format: :turbo_stream), params: { q: "Sync", scope: "hooks" }
    assert_includes response.body, "Sync roster"
  end

  private

  def create_person(name, first_name, team, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: first_name, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager)
    person
  end

  def create_user(email, **flags)
    user = User.create!(email: email, password: "Password1!", **flags)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    user
  end
end
