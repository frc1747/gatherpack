# Team managers used to approve, buy and manage funding sources for their
# teams whatever the settings said. That now takes a row, so this writes
# the old rule out as rows and nothing changes on upgrade: a "Managers of
# each team" approver on every approval step, and a "Managers of each team"
# line in orders_buyers and orders_funding_managers. The admin can then
# remove them on Orders setup. Undoing it removes those rows and lines.
class KeepTeamManagersInOrdersRoles < ActiveRecord::Migration[8.1]
  SETTINGS = %i[orders_buyers orders_funding_managers].freeze

  def up
    execute <<~SQL.squish
      INSERT INTO approval_step_approvers (approval_step_id, kind, created_at, updated_at)
      SELECT approval_steps.id, 'own_team_managers', NOW(), NOW() FROM approval_steps
      WHERE NOT EXISTS (SELECT 1 FROM approval_step_approvers
        WHERE approval_step_id = approval_steps.id AND kind = 'own_team_managers')
    SQL
    SETTINGS.each do |key|
      lines = Orders::Config.grant_lines(Orders::Lists.stored_setting(key))
      next if lines.any? { |line| line.casecmp?(Orders::Reach::OWN_TEAM_LINE) }

      Orders::Lists.restore_setting(key, (lines + [ Orders::Reach::OWN_TEAM_LINE ]).join("\n"))
    end
  end

  def down
    execute "DELETE FROM approval_step_approvers WHERE kind = 'own_team_managers'"
    SETTINGS.each do |key|
      stored = Orders::Lists.stored_setting(key)
      next if stored.nil?

      lines = Orders::Config.grant_lines(stored)
      index = lines.rindex { |line| line.casecmp?(Orders::Reach::OWN_TEAM_LINE) }
      next if index.nil?

      lines.delete_at(index)
      Orders::Lists.restore_setting(key, lines.join("\n"))
    end
  end
end
