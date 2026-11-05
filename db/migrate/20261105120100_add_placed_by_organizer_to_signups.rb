# placed_by_organizer: the sign-up was made from the roster, so it's the taker's
# and not one the signer keeps in their own list. Older rows stay false.
class AddPlacedByOrganizerToSignups < ActiveRecord::Migration[8.1]
  def change
    add_column :signups, :placed_by_organizer, :boolean, default: false, null: false
  end
end
