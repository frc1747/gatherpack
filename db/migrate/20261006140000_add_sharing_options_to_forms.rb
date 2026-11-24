class AddSharingOptionsToForms < ActiveRecord::Migration[8.1]
  def change
    # Who can see a form's totals (counts per choice) without seeing anyone's
    # answers: 0 only people who can see the answers, 1 everyone asked and
    # their guardians, 2 everyone signed in.
    add_column :forms, :totals_visibility, :integer, null: false, default: 0
    # Show leaders a dashboard to-do for responses waiting on them.
    add_column :forms, :leader_todo, :boolean, null: false, default: false
  end
end
