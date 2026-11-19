# The day Orders' own summary email last went to a person (see
# Orders::Reminders.digest), so it goes at most once a day.
class OrderSummarySend < ApplicationRecord
  belongs_to :person

  # Sends the summary (the block, which returns how many people it went to)
  # unless it already went to the person on this day. When nothing went,
  # the day is given back, so a later run can try again. Returns the count.
  def self.once(person, on:)
    mark = create_or_find_by!(person_id: person.id) { |new_mark| new_mark.sent_on = on }
    previous = mark.previously_new_record? ? nil : mark.sent_on
    return 0 if previous && where(id: mark.id).where.not(sent_on: on).update_all(sent_on: on, updated_at: Time.current).zero?

    told = yield.to_i
    if told.zero?
      previous ? where(id: mark.id).update_all(sent_on: previous) : where(id: mark.id).delete_all
    end
    told
  end
end
