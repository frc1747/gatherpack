require "test_helper"

class BadgeAssignmentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @badge = badges(:one)
    @holder = people(:one)
    @outsider = people(:two)
    @candidate = Person.create!(first_name: "Carol", last_name: "Carter", display_name: "Carol Carter")
    Membership.create!(person: @candidate, team: teams(:one))

    @user = users(:one)
    @user.update!(admin: true)
    sign_in @user
  end

  test "candidates lists team members who don't have the badge" do
    get candidates_badge_badge_assignments_path(@badge)

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(@candidate, :candidate)}"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@holder, :candidate)}", count: 0
    assert_select "##{ActionView::RecordIdentifier.dom_id(@outsider, :candidate)}", count: 0
  end

  test "candidates filters by name" do
    get candidates_badge_badge_assignments_path(@badge, candidate_q: "zzz")

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(@candidate, :candidate)}", count: 0
    assert_match "No matches", response.body
  end

  test "create responds with a turbo stream that adds the holder" do
    assert_difference("BadgeAssignment.count") do
      post badge_badge_assignments_path(@badge, format: :turbo_stream), params: { badge_assignment: { person_id: @candidate.id } }
    end

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_match "Added", response.body
    assert_match %(target="badge_assignments"), response.body
  end

  test "create from the regular form still redirects even though Turbo accepts streams" do
    post badge_badge_assignments_path(@badge),
      params: { badge_assignment: { person_id: @candidate.id } },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

    assert_redirected_to badge_badge_assignment_path(@badge, BadgeAssignment.find_by!(badge: @badge, person: @candidate))
  end

  test "create reports a duplicate on the candidate row" do
    assert_no_difference("BadgeAssignment.count") do
      post badge_badge_assignments_path(@badge, format: :turbo_stream), params: { badge_assignment: { person_id: @holder.id } }
    end

    assert_response :unprocessable_entity
    assert_match "already has this badge", response.body
  end

  test "destroy responds with a turbo stream that removes the holder" do
    assignment = badge_assignments(:one)

    assert_difference("BadgeAssignment.count", -1) do
      delete badge_badge_assignment_path(@badge, assignment, format: :turbo_stream)
    end

    assert_response :success
    assert_match %(action="remove"), response.body
  end

  test "candidates requires permission to assign the badge" do
    @user.update!(admin: false)

    get candidates_badge_badge_assignments_path(@badge)

    assert_redirected_to root_path
  end
end
