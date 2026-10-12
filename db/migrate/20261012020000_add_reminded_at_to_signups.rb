# When a sign-up's reminder went out, so a reminder is sent once per due
# date however many jobs were scheduled for it.
class AddRemindedAtToSignups < ActiveRecord::Migration[8.1]
  def change
    add_column :signups, :reminded_at, :datetime
  end
end
