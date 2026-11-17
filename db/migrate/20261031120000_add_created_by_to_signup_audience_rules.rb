# created_by: who added an audience rule. A person or badge rule only opens
# the sheet to people within its creator's reach, unless an admin added it
# (SignupAudienceRule#people_in_reach). Existing rules have no creator and
# are limited to the sheet's team and the teams below it.
class AddCreatedByToSignupAudienceRules < ActiveRecord::Migration[8.1]
  def change
    add_reference :signup_audience_rules, :created_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }
  end
end
