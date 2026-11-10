# One row per retention purge someone ran: what, up to which date, how many
# records and who. Audited, so each purge leaves an audit entry; the purged
# data itself isn't kept.
class CreateHousekeepingPurges < ActiveRecord::Migration[8.1]
  def change
    create_table :housekeeping_purges, id: :uuid do |t|
      t.string :key, null: false
      t.date :cutoff_on, null: false
      t.integer :count, null: false, default: 0
      t.references :person, foreign_key: { on_delete: :nullify }, type: :uuid
      t.timestamps
    end
  end
end
