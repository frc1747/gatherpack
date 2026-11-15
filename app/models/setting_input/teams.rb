# Teams, stored one team name per line, matched exactly as Team.where(name:)
# does. A name used by more than one team is labelled with its path, and
# checking either one stores the name.
class SettingInput::Teams < SettingInput::Checkboxes
  def separator
    "\n"
  end

  def choices
    teams = Team.order(:name).to_a
    by_id = teams.index_by(&:id)
    repeated = teams.map(&:name).tally.select { |_, count| count > 1 }.keys

    teams.map do |team|
      label = repeated.include?(team.name) ? path(team, by_id) : team.name
      [ label, team.name ]
    end
  end

  private

  def normalize(token)
    token.to_s.strip
  end

  def path(team, by_id)
    names = [ team.name ]
    seen = [ team.id ]
    parent = by_id[team.parent_id]
    while parent && !seen.include?(parent.id)
      names.unshift(parent.name)
      seen << parent.id
      parent = by_id[parent.parent_id]
    end
    names.join(" › ")
  end
end
