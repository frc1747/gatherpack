# A set of positions offered at a set of events, with an audience, organizers
# and settings. A slot exists for every position at every event on the sheet;
# people take places in slots (Signup).
class SignupSheet < ApplicationRecord
  has_neat_id :sush
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  SELF_APPROVAL_REASON = "Another organizer needs to mark your own family's sign-ups".freeze

  belongs_to :team
  # Used by Add dates (not built yet).
  belongs_to :event_type, optional: true
  belongs_to :created_by, class_name: "Person", optional: true

  # Must run before the dependent destroys below.
  before_destroy :check_no_signups, prepend: true

  has_many :signup_sheet_organizers, dependent: :destroy
  has_many :organizers, through: :signup_sheet_organizers, source: :person
  has_many :signup_audience_rules, -> { includes_first }, dependent: :destroy, inverse_of: :signup_sheet
  has_many :signup_positions, -> { order(:position, :created_at) }, dependent: :destroy, inverse_of: :signup_sheet
  has_many :signup_sheet_events, dependent: :destroy
  has_many :events, through: :signup_sheet_events
  has_many :signup_slots, through: :signup_positions
  has_many :signups, through: :signup_slots

  enum :status, { draft: 0, open: 1, closed: 2, archived: 3 }, validate: true
  # Who sees names on the sheet page. Organizers always do.
  enum :names_permission, { everyone: 0, organizers: 1 }, prefix: :names, validate: true
  # Whose behalf a sign-up can be on (see #on_behalf_of_choices_for).
  enum :on_behalf_of_mode, { nobody_else: 0, related_people: 1, anyone: 2 }, prefix: :on_behalf_of, validate: true

  validates :title, presence: true
  validates :cancel_cutoff_hours, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :reminder_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  normalizes :others_relationship_type_ids, with: ->(ids) { Array(ids).compact_blank.uniq }

  after_create :add_creator_as_organizer

  scope :visible, -> { where.not(status: :archived) }

  def self.ransackable_attributes(auth_object = nil)
    [ "title", "status", "team_id", "updated_at" ]
  end

  def identifier_name
    title
  end

  def identifier_icon
    "clipboard-list"
  end

  # The badges and teams in the signups_organizers setting, one pair per
  # line ("Badge name > Highest team name"), as [badge, team] pairs. Only
  # admin-assigned badges count. A pair with no team (or an unknown one) has
  # no highest team.
  def self.organizer_grants
    return [] unless GatherPack::Features.enabled?(:badges)

    Settings[:signups_organizers].to_s.lines.filter_map do |line|
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

  def self.grant_holder?(person)
    grants_for(person).any?
  end

  # The teams a grant holder may run sheets for: for each of their grants,
  # the teams they belong to (their own and those above) at or below the
  # grant's highest team, plus the teams below their own (the rule of
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

  # The teams a person may create a sheet for: all for admins, the teams
  # they manage (and those below), and the reach of their grants.
  def self.creatable_team_ids(person)
    return [] if person.nil?
    return Team.ids if person.admin?

    (person.all_managed_teams.ids + organizer_team_ids(person)).uniq
  end

  # Runs this sheet: an admin, a manager of its team or a team above it, or
  # someone on its organizer list who can still create sheets for its team
  # (they lose the sheet when their badge or management goes, or the sheet
  # moves out of their reach).
  def organizer?(person)
    return false if person.nil?
    return true if person.admin? || team.manager?(person)

    signup_sheet_organizers.exists?(person_id: person.id) && self.class.creatable_team_ids(person).include?(team_id)
  end

  # The people who may be added as organizers of this sheet: holders of a
  # granting badge whose reach includes the sheet's team.
  def organizer_candidate?(person)
    self.class.organizer_team_ids(person).include?(team_id)
  end

  # Everyone the sheet is open to: everyone an include rule covers, less
  # everyone an exclude rule covers. With no include rule, the sheet's team
  # and every team below it.
  def audience
    rules = signup_audience_rules.to_a
    rules = rules.reject(&:target_badge?) unless GatherPack::Features.enabled?(:badges)
    included = rules.select(&:effect_include?)
    excluded = rules.select(&:effect_exclude?)

    people = included.any? ? combine(included.map(&:people)) : team.descendant_people
    people = people.where.not(id: combine(excluded.map(&:people)).select(:id)) if excluded.any?
    Person.where(id: people.select(:id))
  end

  def open_to?(person)
    person.present? && audience.where(id: person.id).exists?
  end

  # Who the signer may sign up to take a place: themselves and the people
  # related to them through the sheet's "sign up others" relationship types,
  # as long as the sheet is open to them. The signer must be on the parent
  # side of the relationship ("Parent of" a child they sign up), or either
  # side when the type reads the same both ways ("Sibling of").
  def takers_for(signer)
    return Person.none if signer.nil?

    audience.where(id: [ signer.id ] + related_ids(signer))
  end

  # Whose behalf a sign-up taken by the taker may be on, by the sheet's
  # on_behalf_of_mode: only the taker, the taker or someone related to the
  # signer through the "sign up others" types, or anyone the sheet is open to.
  def on_behalf_of_choices_for(signer, taker)
    return Person.none if taker.nil?

    if on_behalf_of_related_people?
      Person.where(id: [ taker.id ] + related_ids(signer))
    elsif on_behalf_of_anyone?
      Person.where(id: taker.id).or(Person.where(id: audience.select(:id)))
    else
      Person.where(id: taker.id)
    end
  end

  # Whether the two are the same person or related by any relationship type.
  # Organizers can't mark, override for, or move these people's sign-ups.
  def self_or_relative?(organizer, person)
    return false if organizer.nil? || person.nil?
    return true if organizer.id == person.id

    Relationship.where(parent_id: organizer.id, child_id: person.id).or(Relationship.where(parent_id: person.id, child_id: organizer.id)).exists?
  end

  # Why the organizer can't mark this person's sign-ups, if they can't.
  def self_approval_reason(organizer, person)
    SELF_APPROVAL_REASON if self_or_relative?(organizer, person)
  end

  # Whether the person sees names on the sheet page.
  def names_visible_to?(person)
    return false if person.nil?
    return true if organizer?(person)

    names_everyone? && !draft? && takers_for(person).exists?
  end

  # Notes, on behalf of, and the roster are for organizers.
  def details_visible_to?(person)
    organizer?(person)
  end

  # Members can sign up while the sheet is open; organizers also while it's
  # a draft or closed.
  def accepting_signups_from?(person)
    open? || (!archived? && organizer?(person))
  end

  # The people on this sheet's roster, the only people organizers see.
  def roster_people
    ids = signups.select(:person_id)
    Person.where(id: ids).or(Person.where(id: signups.select(:on_behalf_of_id)))
  end

  # Creates any missing slots, one for every position at every event.
  def sync_slots!
    event_ids = signup_sheet_events.pluck(:event_id)
    signup_positions.each { |position| position.add_slots_for!(event_ids) }
  end

  private

  def related_ids(signer)
    types = RelationshipType.where(id: others_relationship_type_ids).to_a
    return [] if types.empty?

    symmetric = types.select { |type| type.parent_label == type.child_label }.map(&:id)
    ids = Relationship.where(parent_id: signer.id, relationship_type_id: types.map(&:id)).pluck(:child_id)
    ids += Relationship.where(child_id: signer.id, relationship_type_id: symmetric).pluck(:parent_id) if symmetric.any?
    ids.uniq
  end

  def combine(relations)
    relations.map { |people| Person.where(id: people.select(:id)) }.reduce(:or)
  end

  def add_creator_as_organizer
    signup_sheet_organizers.create!(person: created_by) if created_by
  end

  def check_no_signups
    return unless signups.exists?

    errors.add(:base, "This sheet has sign-ups, so it can't be deleted. Archive it instead.")
    throw :abort
  end
end
