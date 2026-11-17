require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "destroying an event destroys its check-ins and their field responses" do
    event = events(:one)
    checkin = checkins(:one)
    response = checkin_field_responses(:one)

    assert_difference -> { Checkin.count }, -1 do
      event.destroy!
    end

    assert_not Checkin.exists?(checkin.id)
    assert_not CheckinFieldResponse.exists?(response.id)
  end

  test "destroying an event audit-logs each removed check-in" do
    event = events(:one)
    checkin_ids = event.checkins.pluck(:id)
    assert_not_empty checkin_ids

    event.destroy!

    checkin_ids.each do |id|
      assert AuditLog.exists?(item_type: "Checkin", item_id: id, event: "destroy")
    end
  end
end
