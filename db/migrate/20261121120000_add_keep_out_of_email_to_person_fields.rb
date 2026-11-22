class AddKeepOutOfEmailToPersonFields < ActiveRecord::Migration[8.1]
  def change
    add_column :person_fields, :keep_out_of_email, :boolean, default: false, null: false
  end
end
