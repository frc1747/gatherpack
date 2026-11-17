class AddEventToForms < ActiveRecord::Migration[8.1]
  def change
    add_reference :forms, :event, type: :uuid, foreign_key: { on_delete: :nullify }
  end
end
