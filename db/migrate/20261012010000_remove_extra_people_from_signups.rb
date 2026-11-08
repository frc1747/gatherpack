# Every place is now one sign-up for one person. Sign-ups that still carry
# extra people must be split into one sign-up each before this runs.
class RemoveExtraPeopleFromSignups < ActiveRecord::Migration[8.1]
  def up
    count = select_value("SELECT COUNT(*) FROM signups WHERE extra_people > 0").to_i
    raise "#{count} sign-ups still have extra people; split them into one sign-up each first" if count.positive?

    remove_column :signups, :extra_people
    remove_column :signups, :extra_names
  end

  def down
    add_column :signups, :extra_people, :integer, null: false, default: 0
    add_column :signups, :extra_names, :text
  end
end
