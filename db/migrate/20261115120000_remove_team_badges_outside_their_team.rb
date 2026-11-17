# Membership and team changes used to leave team badges with people no longer
# in the badge's team, where they kept granting access. Removes those once;
# the models now remove them as memberships change. Uses the app's models so
# each removal is recorded in the audit log. Nothing to restore on rollback.
class RemoveTeamBadgesOutsideTheirTeam < ActiveRecord::Migration[8.1]
  def up
    BadgeAssignment.remove_outside_team
  end

  def down
  end
end
