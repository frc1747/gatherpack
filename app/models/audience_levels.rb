# Permission levels relative to a subject (the person some data is about).
# Each level is a fixed set of audience components. Admins can always see
# and edit everything, so they appear in no level. Person fields, check-in
# field read levels, and anything else that guards data about a person share
# these levels.
module AudienceLevels
  PERMISSION_LEVELS = {
    "admin" => [],
    "self" => %i[ subject ],
    "leaders" => %i[ leaders ],
    "self_and_leaders" => %i[ subject leaders ],
    "guardians" => %i[ guardian leaders ],
    "family" => %i[ subject guardian leaders ],
    "team" => %i[ subject guardian leaders teammates ],
    "everyone" => %i[ everyone ]
  }.freeze

  # Explicit integers, so reordering the levels never remaps stored values.
  LEVEL_VALUES = { admin: 0, self: 1, leaders: 2, self_and_leaders: 3, guardians: 4, family: 5, team: 6, everyone: 7 }.freeze

  def self.components(level)
    PERMISSION_LEVELS.fetch(level.to_s)
  end

  # Whether the level reaches people in this component.
  def self.reaches?(level, component)
    level.to_s == "everyone" || components(level).include?(component)
  end

  # Whether everyone the inner level reaches is also reached by the outer one.
  def self.within?(inner, outer)
    outer.to_s == "everyone" || (components(inner) - components(outer)).empty?
  end

  # The people whose data a (non-admin) viewer reaches at this level, as one
  # relation.
  def self.people(level, viewer)
    combine(relations(level, viewer))
  end

  def self.relations(level, viewer)
    components(level).map { |component| component_people(component, viewer) }
  end

  def self.component_people(component, viewer)
    case component
    when :subject then Person.where(id: viewer.id)
    when :guardian then viewer.wards
    when :leaders then viewer.all_managed_people
    when :teammates then Person.joins(:memberships).where(memberships: { team_id: viewer.teams.select(:id) })
    when :everyone then Person.all
    end
  end

  # One Person relation covering every relation given.
  def self.combine(relations)
    relations.empty? ? Person.none : relations.map { |relation| Person.where(id: relation.select(:id)) }.reduce(:or)
  end
end
