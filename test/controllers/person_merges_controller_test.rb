require "test_helper"

class PersonMergesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @admin = User.create!(email: "merge-admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
    @keep = Person.create!(first_name: "Dana", last_name: "Rivers")
    @drop = Person.create!(first_name: "Dana", last_name: "Rivers")
    Membership.create!(person: @drop, team: teams(:one))
    enable_merge(true)
  end

  teardown { enable_merge(@was_enabled) }

  test "an admin previews a merge" do
    sign_in @admin
    get new_person_merge_path(person_merger: { keep_nid: @keep.neat_id, drop_nid: @drop.neat_id })

    assert_response :success
    assert_select "h2", "What will happen"
    assert_select "td", "1"
    assert Person.exists?(@drop.id)
  end

  test "an admin merges two people" do
    sign_in @admin

    assert_difference -> { Person.count }, -1 do
      post person_merges_path, params: { person_merger: { keep_nid: @keep.neat_id, drop_nid: @drop.neat_id } }
    end
    assert_redirected_to person_path(@keep)
    assert_equal [ teams(:one).id ], @keep.memberships.pluck(:team_id)
  end

  test "a refused merge shows why" do
    sign_in @admin
    post person_merges_path, params: { person_merger: { keep_nid: @keep.neat_id, drop_nid: @keep.neat_id } }

    assert_response :unprocessable_entity
    assert Person.exists?(@keep.id)
  end

  test "a non-admin can't preview or merge" do
    manager = User.create!(email: "merge-manager@example.com", password: "Password1!")
    Person.create!(user: manager, first_name: "Max", last_name: "Manager")
      .memberships.create!(team: teams(:one), manager: true)
    sign_in manager

    get new_person_merge_path
    assert_redirected_to root_path

    assert_no_difference -> { Person.count } do
      post person_merges_path, params: { person_merger: { keep_nid: @keep.neat_id, drop_nid: @drop.neat_id } }
    end
    assert_redirected_to root_path
  end

  test "nothing is reachable while the feature is off" do
    enable_merge(false)
    sign_in @admin

    assert_no_difference -> { Person.count } do
      post person_merges_path, params: { person_merger: { keep_nid: @keep.neat_id, drop_nid: @drop.neat_id } }
    end
    assert_redirected_to root_path
  end

  private

  # Flips the flag in memory only: Setting#value= writes the shared settings
  # file, which parallel test workers would race on.
  def enable_merge(on)
    setting = Settings.get(:feature_person_merge)
    @was_enabled = setting.value if @was_enabled.nil?
    setting.instance_variable_set(:@value, on.to_s)
  end
end
