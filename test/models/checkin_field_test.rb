require "test_helper"

class CheckinFieldTest < ActiveSupport::TestCase
  test "answer_count leaves out blank responses" do
    field = checkin_fields(:one)
    assert_equal 1, field.answer_count

    checkin_field_responses(:one).update!(response: "")
    assert_equal 0, field.answer_count
  end

  test "destroying a field destroys its responses, blank or answered, through the audit log" do
    field = checkin_fields(:one)
    CheckinFieldResponse.create!(checkin: checkins(:two), checkin_field: field, response: "")

    assert_difference "CheckinFieldResponse.count", -2 do
      assert_difference "AuditLog.where(item_type: 'CheckinFieldResponse', event: 'destroy').count", 2 do
        field.destroy!
      end
    end
  end
end
