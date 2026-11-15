# A sign-up position rule of kind checklist: only people who finish the
# checklist, or (accept_pending) who are almost done, can take the place.
class AddChecklistToSignupPositionRules < ActiveRecord::Migration[8.1]
  def change
    add_reference :signup_position_rules, :checklist, foreign_key: true, type: :uuid
    add_column :signup_position_rules, :accept_pending, :boolean, default: false, null: false
  end
end
