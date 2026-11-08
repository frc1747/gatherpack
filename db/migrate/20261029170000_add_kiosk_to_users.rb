# A kiosk account runs the time kiosk on a shared device. Only admins mark
# an account as one; no existing account is.
class AddKioskToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :kiosk, :boolean, null: false, default: false
  end
end
