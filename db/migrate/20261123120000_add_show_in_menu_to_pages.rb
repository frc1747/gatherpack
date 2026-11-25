class AddShowInMenuToPages < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :show_in_menu, :boolean, default: false, null: false
  end
end
