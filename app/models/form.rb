# A request for information from a group of people: an audience, a deadline,
# who may answer for each person, who may see the answers, and the questions.
# Each person in the audience (the subject) has at most one FormResponse,
# holding a history of submissions.
class Form < ApplicationRecord
  has_neat_id :frm
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :team
  belongs_to :audience_badge, class_name: "Badge", optional: true
  belongs_to :created_by, class_name: "Person", optional: true
  has_many :form_questions, -> { order(:position, :created_at) }, dependent: :destroy, inverse_of: :form
  has_many :form_responses, dependent: :destroy
  has_many :form_submissions, through: :form_responses
  has_many :form_reminders, dependent: :destroy

  KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

  enum :kind, { general: 0, consent: 1, event_intent: 2 }, validate: true
  enum :status, { draft: 0, open: 1, closed: 2, archived: 3 }, validate: true
  enum :respond_permission, AudienceLevels::LEVEL_VALUES, prefix: :respond, validate: true
  enum :read_permission, AudienceLevels::LEVEL_VALUES, prefix: :read, validate: true
  enum :late_entry, { none: 0, leaders: 1 }, prefix: :late_entry, validate: true

  validates :title, presence: true
  validates :key, presence: true, uniqueness: true, format: { with: KEY_FORMAT, message: "must start with a letter and use only lowercase letters, numbers, and underscores" }
  validate :key_unchanged, on: :update
  validate :respond_within_read
  validate :closes_after_opens

  before_validation :generate_key, on: :create

  scope :visible, -> { where.not(status: :archived) }
  scope :due_to_open, -> { draft.where(opens_at: ..Time.current).where("closes_at IS NULL OR closes_at > ?", Time.current) }
  scope :due_to_close, -> { open.where(closes_at: ..Time.current) }

  def self.ransackable_attributes(auth_object = nil)
    [ "title", "key", "status", "closes_at", "updated_at" ]
  end

  # Opens and closes forms whose dates have passed. Run by FormScheduleJob.
  def self.apply_schedule!
    due_to_open.find_each(&:open!)
    due_to_close.find_each(&:closed!)
  end

  def identifier_name
    title
  end

  def identifier_icon
    "file-signature"
  end

  # Everyone the form asks: direct members of its team or a team below it,
  # narrowed to holders of the audience badge when one is set.
  def audience
    people = team.descendant_people
    people = people.where(id: audience_badge.people.select(:id)) if audience_badge
    Person.where(id: people.select(:id))
  end

  def in_audience?(person)
    audience.where(id: person.id).exists?
  end

  # The people whose responses the viewer may see (or answer), as one
  # relation. Must agree with FormAccess for every subject.
  def readable_subjects_for(viewer)
    subjects_for(viewer, read_permission)
  end

  def respondable_subjects_for(viewer)
    subjects_for(viewer, respond_permission)
  end

  def response_for(subject)
    form_responses.find_by(subject: subject)
  end

  def answerable_questions
    form_questions.select(&:answerable?)
  end

  # Copies the settings and questions, not the responses, as a new draft.
  def duplicate!(title:, key: nil, created_by: nil)
    transaction do
      copy = dup
      copy.assign_attributes(title: title, key: key, status: :draft, content_version: 1, created_by: created_by, opens_at: nil, closes_at: nil)
      copy.save!
      form_questions.each do |question|
        copy.form_questions.create!(question.attributes.except("id", "form_id", "created_at", "updated_at"))
      end
      copy
    end
  end

  private

  def subjects_for(viewer, level)
    return Person.none if viewer.nil?
    return audience if viewer.admin?

    AudienceLevels.people(level, viewer).where(id: audience.select(:id))
  end

  def generate_key
    return if key.present? || title.blank?

    base = title.delete("'’").parameterize(separator: "_").gsub(/[^a-z0-9]+/, "_").sub(/\A[^a-z]+/, "").delete_suffix("_").presence || "form"
    candidate = base
    suffix = 1
    candidate = "#{base}_#{suffix += 1}" while Form.exists?(key: candidate)
    self.key = candidate
  end

  def key_unchanged
    errors.add(:key, "can't be changed once created") if will_save_change_to_key?
  end

  # As with person fields, answering can't reach further than seeing.
  def respond_within_read
    return unless respond_permission && read_permission

    errors.add(:respond_permission, "can't include people who can't see the answers") unless AudienceLevels.within?(respond_permission, read_permission)
  end

  def closes_after_opens
    errors.add(:closes_at, "must be after the opening time") if opens_at && closes_at && closes_at <= opens_at
  end
end
