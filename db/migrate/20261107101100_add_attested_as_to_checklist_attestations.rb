# The "who confirms" level a confirmation satisfied when it was made
# ("person", "guardian" or "manager"), so it keeps counting after its maker
# steps down as a manager or a guardianship ends.
class AddAttestedAsToChecklistAttestations < ActiveRecord::Migration[8.1]
  def change
    add_column :checklist_attestations, :attested_as, :string
  end
end
