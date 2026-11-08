# A named list of items for the people it covers, over a window of dates
# (spec §5). Everyone covered gets a result per item and an overall, stored
# in checklist_results and kept fresh by Checklists::Refresher. See the
# Checklists module for the API other features use.
class Checklist < ApplicationRecord
  has_neat_id :chkl
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  WITHIN_UNITS = %w[days months].freeze

  # The form's start choice ("date", "within", "checklist"); not stored.
  attr_accessor :start_mode

  belongs_to :team
  belongs_to :created_by, class_name: "Person", optional: true

  has_many :checklist_items, dependent: :destroy, inverse_of: :checklist
  has_many :top_level_items, -> { where(parent_id: nil).order(:position, :created_at) }, class_name: "ChecklistItem", inverse_of: :checklist
  has_many :checklist_rules, dependent: :destroy, inverse_of: :checklist
  has_many :population_rules, -> { where(item_id: nil).order(:effect, :target_type, :created_at) }, class_name: "ChecklistRule", inverse_of: :checklist
  has_many :checklist_grants, dependent: :destroy
  has_many :checklist_organizers, dependent: :destroy
  has_many :organizers, through: :checklist_organizers, source: :person
  has_many :checklist_results, dependent: :delete_all
  has_many :checklist_lists, dependent: :destroy
  has_many :checklist_refreshes, dependent: :delete_all

  enum :status, { draft: 0, active: 1, archived: 2 }, validate: true

  validates :title, presence: true
  validates :read_level, inclusion: { in: Checklists::READ_LEVELS.keys - [ "group" ] }
  validates :starts_within_unit, inclusion: { in: WITHIN_UNITS }, allow_blank: true
  validates :starts_within_amount, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :window_in_order
  validate :starts_within_has_unit

  before_validation :clear_unused_start
  after_create :add_creator_as_organizer
  after_commit :refresh_everyone, on: :update

  scope :refreshable, -> { where(status: %i[draft active]) }

  def self.ransackable_attributes(auth_object = nil)
    %w[title team_id status starts_on ends_on updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end

  def identifier_icon
    "list-check"
  end

  # The badges and teams in the checklists_organizers setting, one pair per
  # line ("Badge name > Highest team name"), as [badge, team] pairs. Only
  # admin-assigned badges count. While the setting is blank,
  # commitments_organizers is read instead, where it exists.
  def self.organizer_grants
    return [] unless GatherPack::Features.enabled?(:badges)

    text = Settings[:checklists_organizers].presence
    text ||= Settings[:commitments_organizers] if Settings.get(:commitments_organizers)
    text.to_s.lines.filter_map do |line|
      badge_name, team_name = line.split(">", 2).map(&:strip)
      next if badge_name.blank?

      badge = Badge.added_by_admin.find_by("LOWER(name) = ?", badge_name.downcase)
      next unless badge

      [ badge, team_name.present? ? Team.find_by(name: team_name) : nil ]
    end
  end

  # The teams a grant holder may run checklists for: for each grant whose
  # badge they hold, the teams they belong to (and those above) at or below
  # the grant's highest team, plus the teams below their own.
  def self.organizer_team_ids(person)
    return [] if person.nil?

    badge_ids = BadgeAssignment.where(person_id: person.id).pluck(:badge_id)
    grants = organizer_grants.select { |badge, _| badge_ids.include?(badge.id) }
    return [] if grants.empty?

    direct = person.teams.ids
    below = Checklists.team_subtree_ids(direct)
    above = Checklists.team_ancestor_ids(direct)
    grants.flat_map { |_, cap| cap ? (above + below) & Checklists.team_subtree_ids(cap.id) : below }.uniq
  end

  # The teams a person may make a checklist for: all for admins, the teams
  # they manage (and those below), and the reach of their grants.
  def self.creatable_team_ids(person)
    return [] if person.nil?
    return Team.ids if person.admin?

    managed = Membership.where(person_id: person.id, manager: true).pluck(:team_id)
    (Checklists.team_subtree_ids(managed) + organizer_team_ids(person)).uniq
  end

  # Runs this checklist: an admin, a manager of its team or a team above it,
  # or one of its organizers who can still make checklists for its team.
  def organizer?(person)
    return false if person.nil?
    return true if person.admin? || manager?(person)

    checklist_organizers.exists?(person_id: person.id) && self.class.creatable_team_ids(person).include?(team_id)
  end

  # A manager of the checklist's team or a team above it, or an admin.
  def manager?(person)
    return false if person.nil?
    return true if person.admin?

    Membership.where(person_id: person.id, manager: true, team_id: Checklists.team_ancestor_ids(team_id)).exists?
  end

  def organizer_candidate?(person)
    self.class.organizer_team_ids(person).include?(team_id)
  end

  def window
    Checklists::Window.for(self, Checklists::Context.as_of_for(self, Time.current))
  end

  # Its last day (in the site's time zone) has gone.
  def ended?
    ends_on.present? && Checklists::Context.last_moment(self).past?
  end

  # Checklists with an item requiring this one.
  def dependents
    Checklist.where(id: ChecklistItem.where(kind: "checklist").where("config ->> 'checklist_id' = ?", id.to_s).select(:checklist_id))
  end

  # The checklists this one's items require, directly.
  def required_checklist_ids
    checklist_items.select { |item| item.kind == "checklist" }.filter_map { |item| item.config["checklist_id"].presence }
  end

  # People whose stored overall is accepted. Strict by default (spec
  # §10.3): :met takes met and exempt overalls; pass [:met, :pending] to take
  # people who are in progress too. Only people the checklist covers have an
  # overall, so people it doesn't cover never meet it. A relation, so it
  # combines with other scopes.
  def people_meeting(accept: :met)
    statuses = Array(accept).map(&:to_s)
    statuses |= [ "exempt" ] if statuses.include?("met")
    Person.where(id: checklist_results.where(item_id: nil, status: statuses).select(:person_id))
  end

  def people_covered
    Checklists.people_covered_by(self)
  end

  # Setup problems for organizers: each item's, plus housekeeping notes.
  def problems
    list = checklist_items.flat_map do |item|
      kind = item.kind_class
      next [ "#{item.label}: this kind of item isn't available here" ] unless kind

      kind.problems(item).map { |problem| "#{item.label}: #{problem}" }
    end
    checklist_rules.includes(:item).each do |rule|
      next if rule.target

      where = rule.item ? "#{rule.item.label}: a" : "A"
      list << "#{where} rule's #{rule.target_type == "applicants" ? "team" : rule.target_type} was deleted; it matches nobody"
    end
    if active? && Checklists::Housekeeping.archive_due?(self) && dependents.refreshable.exists?
      list << "Ended, but not archived: #{dependents.refreshable.pluck(:title).to_sentence} still requires it"
    end
    list
  end

  # The last change to its settings, items, rules or grants after it was
  # made, for the banner.
  def last_change
    types = %w[Checklist ChecklistItem ChecklistRule ChecklistGrant]
    ids = [ id ] + checklist_items.ids + checklist_rules.ids + checklist_grants.ids
    current = AuditLog.where(item_id: ids, item_type: types)
    # Removed parts are no longer in the lists above; their last version
    # names this checklist.
    removed = AuditLog.where(item_type: types - [ "Checklist" ], event: "destroy").where("object LIKE ?", "%#{id}%")
    current.or(removed).order(created_at: :desc).first
  end

  # Who made a change, as a role ("an admin", "a manager", "an organizer").
  def role_of(change)
    person = User.find_by(id: change&.whodunnit)&.person
    if person.nil? then "someone"
    elsif person.admin? then "an admin"
    elsif manager?(person) then "a manager"
    elsif checklist_organizers.exists?(person_id: person.id) then "an organizer"
    else "someone"
    end
  end

  # "Changed 6 Nov 2026 by an organizer: item Safety edited", for the banner.
  # Without details (for viewers who don't see everything) only "Changed
  # <date> by <role>", so it names no item they can't see.
  def last_change_text(details: true)
    change = last_change
    return unless change
    return "Changed #{I18n.l(change.created_at.to_date, format: :long)} by #{role_of(change)}" unless details

    what = case change.item_type
    when "Checklist" then "settings"
    when "ChecklistItem" then "item #{checklist_items.find_by(id: change.item_id)&.label || change.reify&.label}".strip
    when "ChecklistRule" then "who it covers"
    else "who can see it"
    end
    "Changed #{I18n.l(change.created_at.to_date, format: :long)} by #{role_of(change)}: #{what} #{change.event == "destroy" ? "removed" : "edited"}"
  end

  private

  def window_in_order
    errors.add(:ends_on, "must be on or after the start") if starts_on && ends_on && ends_on < starts_on
  end

  def starts_within_has_unit
    errors.add(:starts_within_unit, "must be days or months") if starts_within_amount.present? && starts_within_unit.blank?
  end

  def clear_unused_start
    self.starts_on = nil if starts_within_amount.present?
    self.starts_within_unit = nil if starts_within_amount.blank?
  end

  def add_creator_as_organizer
    checklist_organizers.create!(person: created_by) if created_by
  end

  def refresh_everyone
    return unless Checklists.enabled? && !archived?
    return unless (saved_changes.keys & %w[team_id starts_on starts_within_amount starts_within_unit ends_on status]).any?

    Checklists.mark(self, :all)
  end
end
