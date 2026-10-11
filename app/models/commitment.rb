# Who owes, how much, over what period, and which sources count (spec §4).
# People in the owing team (and the teams below it), optionally only those
# holding the owing badge, each owe base_amount in the commitment's unit.
# Progress is computed from the sources and adjustments, never stored.
class Commitment < ApplicationRecord
  has_neat_id :cmt
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  SELF_APPROVAL_REASON = "Another organizer needs to adjust your own family's credit".freeze

  belongs_to :team
  belongs_to :owing_team, class_name: "Team"
  belongs_to :owing_badge, class_name: "Badge", optional: true
  belongs_to :created_by, class_name: "Person", optional: true

  has_many :commitment_organizers, dependent: :destroy
  has_many :organizers, through: :commitment_organizers, source: :person
  has_many :commitment_sources, -> { order(:position, :created_at) }, dependent: :destroy, inverse_of: :commitment
  has_many :commitment_adjustments, dependent: :destroy

  # Which credit completes the commitment. Pages always show both.
  enum :counts_when, { confirmed: 0, planned: 1 }, prefix: :counts, validate: true

  validates :title, presence: true
  validates :unit, presence: true
  validates :base_amount, numericality: { only_integer: true, greater_than: 0 }
  validates :starts_on, presence: true
  validates :ends_on, presence: true
  validate :period_in_order
  validate :owing_team_in_reach

  after_create :add_creator_as_organizer

  def self.ransackable_attributes(auth_object = nil)
    [ "title", "team_id", "starts_on", "ends_on", "updated_at" ]
  end

  def identifier_name
    title
  end

  def identifier_icon
    "list-check"
  end

  # The badges and teams in the commitments_organizers setting, one pair per
  # line ("Badge name > Highest team name"), as [badge, team] pairs. Only
  # admin-assigned badges count. A pair with no team (or an unknown one) has
  # no highest team.
  def self.organizer_grants
    return [] unless GatherPack::Features.enabled?(:badges)

    Settings[:commitments_organizers].to_s.lines.filter_map do |line|
      badge_name, team_name = line.split(">", 2).map(&:strip)
      next if badge_name.blank?

      badge = Badge.added_by_admin.find_by("LOWER(name) = ?", badge_name.downcase)
      next unless badge

      [ badge, team_name.present? ? Team.find_by(name: team_name) : nil ]
    end
  end

  # The grants whose badge this person holds.
  def self.grants_for(person)
    return [] if person.nil?

    badge_ids = BadgeAssignment.where(person_id: person.id).pluck(:badge_id)
    organizer_grants.select { |badge, _team| badge_ids.include?(badge.id) }
  end

  # The teams a grant holder may run commitments for: for each of their
  # grants, the teams they belong to (their own and those above) at or below
  # the grant's highest team, plus the teams below their own (the rule of
  # Form.creator_team_ids). Several grants give the union.
  def self.organizer_team_ids(person)
    grants = grants_for(person)
    return [] if grants.empty?

    direct = person.teams.ids
    below = (direct + Team.where(id: direct).flat_map(&:all_descendant_ids)).uniq
    above = person.all_ancestor_teams.ids

    grants.flat_map do |_badge, cap|
      next below unless cap

      within = [ cap.id ] + cap.all_descendant_ids
      (above + below) & within
    end.uniq
  end

  # The teams a person may create a commitment for: all for admins, the
  # teams they manage (and those below), and the reach of their grants.
  def self.creatable_team_ids(person)
    return [] if person.nil?
    return Team.ids if person.admin?

    (person.all_managed_teams.ids + organizer_team_ids(person)).uniq
  end

  # Runs this commitment: an admin, a manager of its team or a team above
  # it, or someone on its organizer list who can still create commitments
  # for its team.
  def organizer?(person)
    return false if person.nil?
    return true if person.admin? || team.manager?(person)

    commitment_organizers.exists?(person_id: person.id) && self.class.creatable_team_ids(person).include?(team_id)
  end

  # Holders of a granting badge whose reach includes the commitment's team.
  def organizer_candidate?(person)
    self.class.organizer_team_ids(person).include?(team_id)
  end

  # Whether the two are the same person or related by any relationship type.
  # Nobody adjusts credit for themselves or a relative.
  def self_or_relative?(organizer, person)
    return false if organizer.nil? || person.nil?
    return true if organizer.id == person.id

    Relationship.where(parent_id: organizer.id, child_id: person.id).or(Relationship.where(parent_id: person.id, child_id: organizer.id)).exists?
  end

  def self_approval_reason(organizer, person)
    SELF_APPROVAL_REASON if self_or_relative?(organizer, person)
  end

  # Everyone who owes: the owing team and every team below it, narrowed to
  # holders of the owing badge when there is one.
  def owing_people
    people = owing_team.descendant_people
    people = people.where(id: BadgeAssignment.where(badge_id: owing_badge_id).select(:person_id)) if owing_badge_id
    Person.where(id: people.select(:id))
  end

  def covers?(person)
    person.present? && owing_people.exists?(id: person.id)
  end

  # Progress for these people (default: everyone who owes), keyed by person id.
  def progress(people = owing_people)
    Commitments::Progress.for(self, people)
  end

  def progress_for(person)
    progress([ person ])[person.id]
  end

  # The commitment's team and every team below it. Sources count activity
  # within this part of the tree.
  def team_and_below_ids
    [ team_id ] + team.all_descendant_ids
  end

  # The period as a time range in the site's time zone, ends_on included.
  def period_times
    starts_on.in_time_zone.beginning_of_day..ends_on.in_time_zone.end_of_day
  end

  private

  def period_in_order
    errors.add(:ends_on, "can't be before the start") if starts_on && ends_on && ends_on < starts_on
  end

  # Organizers see the owing people's progress, so they must be people the
  # commitment's team reaches.
  def owing_team_in_reach
    return if team.nil? || owing_team_id.nil?

    errors.add(:owing_team_id, "must be #{team.name} or a team below it") unless team_and_below_ids.include?(owing_team_id)
  end

  def add_creator_as_organizer
    commitment_organizers.create!(person: created_by) if created_by
  end
end
