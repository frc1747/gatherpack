# Teams, stored one team name per line, matched exactly as Team.where(name:)
# does. The stored name can't tell apart teams that share it, so they are one
# choice, labelled with each team's path: "Mechanical (A › Mechanical,
# B › Mechanical)".
class SettingInput::Teams < SettingInput::Checkboxes
  def separator
    "\n"
  end

  def choices
    teams = Team.order(:name).to_a
    by_id = teams.index_by(&:id)

    teams.group_by(&:name).map do |name, named|
      label = named.one? ? name : "#{name} (#{named.map { |team| path(team, by_id) }.sort.join(", ")})"
      [ label, name ]
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
