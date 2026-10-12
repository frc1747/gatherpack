# Who owes, how much, over what period, and which sources count (spec §4).
# People in the owing team (and the teams below it), optionally only those
# holding the owing badge, less holders of the exempt badge, owe
# base_amount in the commitment's unit. With a group relationship type they
# owe together in groups (spec §4.4): base_amount for the first member and
# additional_amount for each other. Progress is computed from the sources
# and adjustments, never stored.
#
# The API for reports and other features:
#
#   commitment.covers?(person)       # owes it (in the owing population, not exempt)
#   commitment.progress_for(person)  # their group's Commitments::Progress, nil if not covered
#   commitment.progress(people)      # the same for many people at once, keyed by person id;
#                                    # build it once for a list instead of calling progress_for
#                                    # per person (a few queries in all, whatever the size)
#   commitment.group_for(person)     # the owing people who owe with them, themselves included
#
# A Progress answers owed, confirmed, planned, remaining, met?, members
# (the group's owing people) and lines (the breakdown, one Line per source
# with its confirmed and planned credits, plus adjustments). See
# Commitments::Progress. Nothing else of the commitments layer is meant to
# be read from outside it.
class Commitment < ApplicationRecord
  has_neat_id :cmt
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  SELF_APPROVAL_REASON = "Another organizer needs to adjust your own family's credit".freeze

  belongs_to :team
  belongs_to :owing_team, class_name: "Team"
  belongs_to :owing_badge, class_name: "Badge", optional: true
  belongs_to :exempt_badge, class_name: "Badge", optional: true
  belongs_to :group_relationship_type, class_name: "RelationshipType", optional: true
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
  validates :additional_amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :starts_on, presence: true
  validates :ends_on, presence: true
  validate :period_in_order
  validate :owing_team_in_reach
  validate :exempt_badge_differs

  after_create :add_creator_as_organizer
  after_save :forget_groups

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

  # Whether the organizer is, or is related by any relationship type to,
  # anyone in the person's group. Credit pools in a group, so adjusting any
  # member's is adjusting the whole group's.
  def self_or_relative_in_group?(organizer, person)
    return false if organizer.nil? || person.nil?

    ids = group_ids_for(person.id).presence || [ person.id ]
    return true if ids.include?(organizer.id)

    Relationship.where(parent_id: organizer.id, child_id: ids).or(Relationship.where(parent_id: ids, child_id: organizer.id)).exists?
  end

  def self_approval_reason(organizer, person)
    SELF_APPROVAL_REASON if self_or_relative_in_group?(organizer, person)
  end

  # Everyone who owes: the owing team and every team below it, narrowed to
  # holders of the owing badge when there is one, less holders of the
  # exempt badge.
  def owing_people
    people = owing_team.descendant_people
    people = people.where(id: BadgeAssignment.where(badge_id: owing_badge_id).select(:person_id)) if owing_badge_id
    people = people.where.not(id: BadgeAssignment.where(badge_id: exempt_badge_id).select(:person_id)) if exempt_badge_id
    Person.where(id: people.select(:id))
  end

  def covers?(person)
    person.present? && owing_people.exists?(id: person.id)
  end

  def grouped?
    group_relationship_type_id.present?
  end

  # Progress for these people (default: everyone who owes), keyed by person
  # id. Each person's value is their group's progress, shared by the
  # group's members; people the commitment doesn't cover are left out.
  def progress(people = owing_people)
    Commitments::Progress.for(self, people)
  end

  # The person's group's progress (theirs alone when ungrouped), or nil
  # when the commitment doesn't cover them.
  def progress_for(person)
    progress([ person ])[person.id] if person
  end

  # The owing people in the person's group, by name; just the person when
  # ungrouped or unconnected, and none when they don't owe.
  def group_for(person)
    ids = group_ids_for(person.id)
    Person.where(id: ids).order(:last_name, :first_name).to_a
  end

  # The owing people's groups: person id => the ids of their group's
  # members. Owing people related through the group relationship type,
  # directly or through one person who doesn't owe related to both (two
  # students sharing a parent), are one group, and so is a chain of those
  # through owing members (half-siblings: A and B share a parent, B and C
  # another). Two people who don't owe never link: with Parent of, a
  # recorded grandparent doesn't make cousins one group. Built once per
  # instance for the whole owing population; reload to see later changes.
  def group_index
    @group_index ||= build_group_index
  end

  def group_ids_for(person_id)
    group_index.fetch(person_id, [])
  end

  # Someone related through the group relationship type to a member of a
  # group without owing themselves (a parent). They see that group's
  # progress, read-only.
  def group_relative?(person)
    !covers?(person) && related_group_member_id(person).present?
  end

  # Whether the viewer is related through the group relationship type to a
  # member of the person's group.
  def group_relative_of?(viewer, person)
    return false unless grouped? && viewer && person

    (group_relative_ids(viewer) & group_ids_for(person.id)).any?
  end

  # The progress a person sees as their own: their group's if they owe,
  # the group of the people they're related to through the group
  # relationship type if not (a parent's), or nil.
  def progress_seen_by(person)
    return if person.nil?

    progress_for(person) || related_group_member_id(person)&.then { |id| progress([ Person.find(id) ])[id] }
  end

  def reload(*)
    forget_groups
    super
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

  def forget_groups
    @group_index = nil
  end

  def build_group_index
    owing_ids = owing_people.pluck(:id)
    return owing_ids.to_h { |id| [ id, [ id ] ] } unless grouped?

    # Union-find over the relationships of the type with an owing person
    # on at least one side, in one query. A relationship between two people
    # who don't owe is never loaded, so a link goes owing -> X -> owing at
    # most, never X -> Y.
    roots = {}
    root = ->(id) { roots[id].nil? || roots[id] == id ? id : (roots[id] = root.(roots[id])) }
    pairs = Relationship.where(relationship_type_id: group_relationship_type_id)
      .where(parent_id: owing_ids).or(Relationship.where(relationship_type_id: group_relationship_type_id, child_id: owing_ids))
      .pluck(:parent_id, :child_id)
    pairs.each { |a, b| roots[root.(a)] = root.(b) unless root.(a) == root.(b) }

    groups = owing_ids.group_by { |id| root.(id) }.values
    groups.each_with_object({}) { |ids, index| ids.each { |id| index[id] = ids } }
  end

  # The people related to this one through the group relationship type.
  def group_relative_ids(person)
    Relationship.where(relationship_type_id: group_relationship_type_id)
      .where(parent_id: person.id).or(Relationship.where(relationship_type_id: group_relationship_type_id, child_id: person.id))
      .pluck(:parent_id, :child_id).flatten.uniq - [ person.id ]
  end

  # An owing person this one is related to through the group relationship
  # type. A person outside the owing population connects all of theirs, so
  # they're all in one group.
  def related_group_member_id(person)
    return unless grouped? && person

    group_relative_ids(person).find { |id| group_index.key?(id) }
  end

  def exempt_badge_differs
    errors.add(:exempt_badge_id, "can't be the badge of those who owe") if exempt_badge_id.present? && exempt_badge_id == owing_badge_id
  end

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
