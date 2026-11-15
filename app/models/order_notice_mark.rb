# One once-only reminder sent for a request (see Orders::Reminders).
class OrderNoticeMark < ApplicationRecord
  belongs_to :order_request

  # Takes the reminder of this kind for the occasion, once. True for the
  # caller that got it, false when it has already gone out for this
  # occasion (also when two jobs race for it).
  def self.claim(order_request, kind, detail)
    mark = create_or_find_by!(order_request_id: order_request.id, kind: kind) do |new_mark|
      new_mark.detail = detail
      new_mark.sent_at = Time.current
    end
    return true if mark.previously_new_record?

    where(id: mark.id).where.not(detail: detail).update_all(detail: detail, sent_at: Time.current, updated_at: Time.current) == 1
  end
end
