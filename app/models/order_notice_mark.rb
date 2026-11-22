# One once-only reminder sent for a request (see Orders::Reminders).
class OrderNoticeMark < ApplicationRecord
  belongs_to :order_request

  # Takes the reminder of this kind for the occasion, once. True for the
  # caller that got it, false when it has already gone out for this
  # occasion (also when two jobs race for it).
  def self.claim(order_request, kind, detail)
    !claim_state(order_request, kind, detail).nil?
  end

  # Sends the reminder (the block, which returns how many people it went
  # to) if this occasion hasn't been reminded. When no one was told, the
  # claim is given back, so a later run can try again. Returns the count.
  def self.once(order_request, kind, detail)
    previous = claim_state(order_request, kind, detail)
    return 0 if previous.nil?

    told = yield.to_i
    release(order_request, kind, previous) if told.zero?
    told
  end

  # What the mark held before this claim ({} for a new one), or nil when
  # the occasion was already claimed.
  def self.claim_state(order_request, kind, detail)
    mark = create_or_find_by!(order_request_id: order_request.id, kind: kind) do |new_mark|
      new_mark.detail = detail
      new_mark.sent_at = Time.current
    end
    return {} if mark.previously_new_record?

    before = mark.slice(:detail, :sent_at)
    where(id: mark.id).where.not(detail: detail).update_all(detail: detail, sent_at: Time.current, updated_at: Time.current) == 1 ? before : nil
  end

  def self.release(order_request, kind, previous)
    mark = find_by(order_request_id: order_request.id, kind: kind)
    previous.empty? ? mark&.destroy : mark&.update_columns(previous)
  end
  private_class_method :claim_state, :release
end
