# Housekeeping archives events and announcements by date. Neither has an
# archived status, so each gets a nullable archived_at (set means archived).
class AddArchivedAtToEventsAndAnnouncements < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :archived_at, :datetime
    add_column :announcements, :archived_at, :datetime
  end
end
