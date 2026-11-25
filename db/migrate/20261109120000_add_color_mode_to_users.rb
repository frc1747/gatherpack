class AddColorModeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :color_mode, :string
  end
end
