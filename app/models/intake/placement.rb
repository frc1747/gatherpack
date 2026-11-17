# A registration's placement lists, applied when an application from it is
# approved (or when someone joins a team that needs no approval): also add to
# these teams, also give these badges, add a guardian to these teams, and the
# one team the approving manager picks. Every step skips what is already
# there, so running it twice adds nothing.
class Intake::Placement
  attr_reader :person, :registration, :pick_team

  # approver: the login deciding, or for a team that needs no approval the
  # login joining (or adding the person). Badges are given only when it may
  # assign them, so a list an admin set up gives a manager's approvals, or
  # someone's own join, only the badges they could give by hand. Without one,
  # no badges.
  def initialize(application: nil, person: nil, registration: nil, pick_team: nil, approver: nil)
    @person = person || application&.person
    @registration = registration || application&.registration
    @pick_team = pick_team
    @approver = approver
  end

  def pick_teams
    registration ? registration.pick_one_teams : Team.none
  end

  def pick_required?
    registration.present? && registration.pick_one_required? && pick_teams.exists?
  end

  def missing_pick?
    pick_required? && pick_team.nil?
  end

  # A pick-one team whose name contains one of the person's field values
  # (a graduation year in "Class of 2031"). A suggestion for the view only.
  def suggested_pick
    values = person.person_field_values.includes(:person_field).map { |row| Array(row.person_field.cast(row.value)).join(" ").strip.downcase }
    values = values.select { |value| value.length >= 2 }
    pick_teams.detect { |team| values.any? { |value| team.name.downcase.include?(value) } }
  end

  # Names of what approval would add, for "Will also join: ... Will get: ...".
  def preview
    return { teams: [], badges: [], guardian_teams: [] } unless registration
    {
      teams: registration.also_add_teams.where.not(id: person.memberships.select(:team_id)).pluck(:name),
      badges: registration.badges.where.not(id: person.badge_assignments.select(:badge_id)).select { |badge| may_give?(badge) }.map(&:name),
      guardian_teams: person.guardians.exists? ? registration.guardian_also_add_teams.pluck(:name) : []
    }
  end

  # Adds what is missing. Returns the names of what was added.
  def apply!
    added = { teams: [], badges: [], guardian_teams: [] }
    return added unless registration

    ActiveRecord::Base.transaction do
      teams = registration.also_add_teams.to_a
      teams << pick_team if pick_team && pick_teams.include?(pick_team)
      teams.each { |team| added[:teams] << team.name if add_membership(person, team) }
      registration.badges.each { |badge| added[:badges] << badge.name if give_badge(badge) }
      added[:guardian_teams] = add_guardians_to_teams
    end
    added
  end

  def add_guardians_to_teams
    return [] unless registration
    teams = registration.guardian_also_add_teams.to_a
    person.guardians.flat_map do |guardian|
      teams.select { |team| add_membership(guardian, team) }.map(&:name)
    end.uniq
  end

  private

  def add_membership(member, team)
    return false if member.memberships.exists?(team: team)
    Membership.create!(person: member, team: team, manager: false)
    true
  end

  # A team badge needs its holder on the team; one that can't be given is
  # left out rather than stopping the approval.
  def give_badge(badge)
    return false if person.badge_assignments.exists?(badge: badge) || !may_give?(badge)
    BadgeAssignment.new(person: person, badge: badge).save
  end

  def may_give?(badge)
    @approver&.person.present? && BadgeAssignmentPolicy.new(@approver, BadgeAssignment.new(person: person, badge: badge)).create?
  end
end
