class AddExpiryToForms < ActiveRecord::Migration[8.1]
  def change
    # When responses stop counting: on a date for everyone, or a number of
    # months after each one was signed. At most one is set; neither means
    # responses never expire.
    add_column :forms, :expires_on, :date
    add_column :forms, :valid_for_months, :integer
  end
end
