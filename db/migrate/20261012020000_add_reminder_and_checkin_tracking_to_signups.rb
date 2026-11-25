# reminded_at: when a sign-up's reminder went out, so a reminder is sent
# once per due date however many jobs were scheduled for it.
# fulfilled_by_checkin_id: the check-in that fulfilled the sign-up, so
# deleting that check-in undoes only its own fulfilment, not an organizer's
# mark. No foreign key: the id is read after the check-in is deleted.
class AddReminderAndCheckinTrackingToSignups < ActiveRecord::Migration[8.1]
  def change
    add_column :signups, :reminded_at, :datetime
    add_column :signups, :fulfilled_by_checkin_id, :uuid
    add_index :signups, :fulfilled_by_checkin_id
  end
end
