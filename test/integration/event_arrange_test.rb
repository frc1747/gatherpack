require "test_helper"

class EventArrangeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(admin: true)
    @event = events(:one)
    @response_record = checkin_field_responses(:one)
  end

  test "dragging a response saves it through the URL the page renders" do
    sign_in @user

    get arrange_event_path(@event, field_id: @response_record.checkin_field_id)
    assert_response :success
    url = css_select("[data-controller=arrange]").first["data-arrange-field-update-url-value"]
    assert_equal field_update_event_path(@event), url

    patch url, params: { field_id: @response_record.id, response: "Group B" }, as: :json

    assert_response :no_content
    assert_equal "Group B", @response_record.reload.response
  end

  test "moving a response to unassigned stores nil and keeps a single unassigned group" do
    other = Checkin.create!(event: @event, person: people(:two), created_by: "test")
    other.refresh_fields
    other.checkin_field_responses.find_by!(checkin_field: @response_record.checkin_field).update!(response: nil)
    sign_in @user

    patch field_update_event_path(@event), params: { field_id: @response_record.id, response: nil }, as: :json

    assert_response :no_content
    assert_nil @response_record.reload.response

    get arrange_event_path(@event, field_id: @response_record.checkin_field_id)
    assert_response :success
    assert_select ".arranging-label", text: "unassigned", count: 1
    assert_select ".arranging-container[data-arranging-container='']", count: 1 do
      assert_select ".arranging-badge", count: 2
    end
  end
end
