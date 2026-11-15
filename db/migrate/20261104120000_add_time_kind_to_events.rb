class AddTimeKindToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :time_kind, :string, default: "timed", null: false
  end
end
