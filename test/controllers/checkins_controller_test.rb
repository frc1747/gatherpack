require "test_helper"

class CheckinsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @event = events(:one)
    @checked_in = people(:one)
    @candidate = Person.create!(first_name: "Carol", last_name: "Carter", display_name: "Carol Carter")

    @user = users(:one)
    @user.update!(admin: true)
    sign_in @user
  end

  def candidate_id(record)
    ActionView::RecordIdentifier.dom_id(record, :candidate)
  end

  test "candidates list people who aren't checked in" do
    get candidates_event_checkins_path(@event)

    assert_response :success
    assert_select "##{candidate_id(@candidate)}"
    assert_select "##{candidate_id(@checked_in)}", count: 0
  end

  test "checking someone in streams them into the grid" do
    assert_difference("@event.checkins.count") do
      post event_checkins_path(@event, format: :turbo_stream), params: { checkin: { person_id: @candidate.id } }
    end

    assert_response :success
    assert_match "Added", response.body
    assert_match %(target="checkins"), response.body
    assert_equal @event.checkin_field_responses.where(checkin: @event.checkins.find_by(person: @candidate)).count,
      @event.event_type.checkin_fields.count
  end

  test "a full event reports the limit on the candidate row" do
    @event.update!(checkin_limit: 1)

    assert_no_difference("Checkin.count") do
      post event_checkins_path(@event, format: :turbo_stream), params: { checkin: { person_id: @candidate.id } }
    end

    assert_response :unprocessable_entity
    assert_match "exceeds checkin limit", response.body
  end

  test "the regular form still redirects" do
    post event_checkins_path(@event),
      params: { checkin: { person_id: @candidate.id } },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

    assert_redirected_to event_path(@event)
  end

  test "candidates are refused on a locked event for non-managers" do
    @user.update!(admin: false)
    @event.update!(locked: true)

    get candidates_event_checkins_path(@event)

    assert_redirected_to root_path
  end
end
