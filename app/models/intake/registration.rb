# A registration link: the dates it is open, the teams people may apply to,
# and what approval adds them to (placement lists). Belongs to a team, whose
# managers run it. Open means now is between opens_at and closes_at (no end
# when closes_at is blank); there is no state column.
class Intake::Registration < ApplicationRecord
  has_neat_id :ireg
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :team
  belongs_to :created_by, class_name: "Person", optional: true
  belongs_to :successor, class_name: "Intake::Registration", optional: true
  belongs_to :guardian_relationship_type, class_name: "RelationshipType", optional: true
  has_many :registration_teams, class_name: "Intake::RegistrationTeam", dependent: :destroy, inverse_of: :registration
  has_many :registration_badges, class_name: "Intake::RegistrationBadge", dependent: :destroy, inverse_of: :registration
  has_many :badges, through: :registration_badges
  has_many :entries, class_name: "Intake::Entry", dependent: :destroy, inverse_of: :registration
  has_many :membership_applications, foreign_key: :registration_id, dependent: :nullify, inverse_of: :registration

  SLUG_FORMAT = /\A[a-z0-9][a-z0-9-]{3,63}\z/

  validates :title, presence: true
  validates :opens_at, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: SLUG_FORMAT, message: "must be 4 to 64 lowercase letters, digits or dashes" }
  validate :closes_after_opening
  validate :has_teams_to_apply_to
  validate :guardian_type_is_a_guardianship
  validate :kiosk_fields_are_custom

  before_validation :assign_slug, on: :create
  after_save :save_team_lists

  scope :open_now, ->(at = Time.current) { where("opens_at <= :at AND (closes_at IS NULL OR closes_at > :at)", at: at) }

  # Registrations closed longer than intake_archive_days are archived: left
  # off the list, with their entries and counts kept. Blank means never.
  scope :not_archived, -> {
    days = Intake.setting(:intake_archive_days, nil)
    days ? where("closes_at IS NULL OR closes_at > ?", days.days.ago) : all
  }

  def self.ransackable_attributes(auth_object = nil)
    %w[title opens_at closes_at created_at updated_at]
  end

  # Team lists by kind (apply, also_add, pick_one, guardian_also_add), read
  # and assigned as ids so the form can use plain multi-selects.
  Intake::RegistrationTeam.kinds.each_key do |kind|
    define_method(:"#{kind}_team_ids") do
      @pending_team_ids&.key?(kind) ? @pending_team_ids[kind] : registration_teams.select { |rt| rt.kind == kind }.map(&:team_id)
    end

    define_method(:"#{kind}_team_ids=") do |ids|
      (@pending_team_ids ||= {})[kind] = Array(ids).compact_blank.uniq
    end

    define_method(:"#{kind}_teams") do
      Team.where(id: public_send(:"#{kind}_team_ids")).order(:name)
    end
  end

  # The kiosk's first-step questions: custom person fields (never the
  # built-in profile data, such as birthday or phone), in field order.
  def kiosk_fields
    PersonField.in_use.custom.where(id: kiosk_field_ids).ordered
  end

  def kiosk_field_ids=(ids)
    super(Array(ids).compact_blank.uniq)
  end

  def open?(at = Time.current)
    opens_at.present? && opens_at <= at && (closes_at.nil? || at < closes_at)
  end

  def not_yet_open?(at = Time.current)
    opens_at.present? && at < opens_at
  end

  def closed?(at = Time.current)
    closes_at.present? && closes_at <= at
  end

  def self_service_open?
    self_service? && open?
  end

  def kiosk_open?
    kiosk? && open?
  end

  # Entries still waiting for their email to be confirmed, within the time
  # they are kept.
  def unverified_entries
    entries.unverified.where(created_at: Intake::Entry.retention_cutoff..)
  end

  def at_entry_cap?
    unverified_entries.count >= Intake.setting(:intake_entry_cap, 500)
  end

  # Unsaved copy with the same lists and dates moved on by the gap between
  # this one's open and close dates, for a person to confirm.
  def copy
    copy = self.class.new(attributes.slice("team_id", "title", "description", "self_service", "kiosk", "checklist_id",
      "gate_approval", "pick_one_required", "guardian_relationship_type_id", "kiosk_field_ids"))
    if closes_at
      gap = closes_at - opens_at
      copy.opens_at = opens_at + gap
      copy.closes_at = closes_at + gap
    end
    Intake::RegistrationTeam.kinds.each_key { |kind| copy.public_send(:"#{kind}_team_ids=", public_send(:"#{kind}_team_ids")) }
    copy.badge_ids = badge_ids
    copy
  end

  def identifier_icon
    "clipboard-list"
  end

  def identifier_name
    title
  end

  private

  def assign_slug
    self.slug = SecureRandom.alphanumeric(12).downcase if slug.blank?
  end

  def closes_after_opening
    return unless opens_at && closes_at
    errors.add(:closes_at, "must be after it opens") if closes_at <= opens_at
  end

  def has_teams_to_apply_to
    errors.add(:apply_team_ids, "choose at least one team people can join") if apply_team_ids.empty?
  end

  def guardian_type_is_a_guardianship
    return if guardian_relationship_type.nil? || guardian_relationship_type.guardianship?
    errors.add(:guardian_relationship_type, "must be a guardianship type")
  end

  def kiosk_fields_are_custom
    return if kiosk_field_ids.blank?
    errors.add(:kiosk_field_ids, "can only be custom person fields") if PersonField.custom.where(id: kiosk_field_ids).count != kiosk_field_ids.size
  end

  def save_team_lists
    return unless @pending_team_ids
    @pending_team_ids.each do |kind, ids|
      existing = registration_teams.where(kind: kind)
      existing.where.not(team_id: ids).destroy_all
      (ids - existing.pluck(:team_id)).each { |team_id| registration_teams.create!(kind: kind, team_id: team_id) }
    end
    @pending_team_ids = nil
    registration_teams.reset
  end
end
