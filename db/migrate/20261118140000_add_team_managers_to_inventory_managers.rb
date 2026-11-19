# Team managers used to manage their teams' inventory whatever
# inventory_managers said; now only its rows grant (Inventory::Reach). So
# that nothing changes on upgrade, this writes the old rule out as the row
# "Managers of each team", appended to the saved setting (or as the whole
# setting when none is saved). The admin can remove it on Inventory setup.
# Down takes out the row up added; the code before this change reads the
# line as a badge that doesn't exist, so a site that already had it loses
# nothing either.
class AddTeamManagersToInventoryManagers < ActiveRecord::Migration[8.1]
  KEY = :inventory_managers
  ROW = "Managers of each team".freeze

  def up
    self.class.add_row
  end

  def down
    self.class.remove_row
  end

  def self.add_row
    return unless defined?(Settings)

    lines = stored_lines
    return if lines.any? { |line| line.casecmp?(ROW) }

    store((lines + [ ROW ]).join("\n"))
  end

  def self.remove_row
    return unless defined?(Settings)

    lines = stored_lines
    index = lines.rindex { |line| line.casecmp?(ROW) }
    return if index.nil?

    lines.delete_at(index)
    store(lines.join("\n"))
  end

  def self.stored_lines
    Settings.instance.stored_values[KEY].to_s.lines.map(&:strip).compact_blank
  end

  def self.store(text)
    store = Settings.instance.store
    store.transaction { store[KEY] = text }
  end
end
