# A request for information from a group of people: an audience, a deadline,
# who may answer for each person, who may see the answers, and the questions.
# Each person in the audience (the subject) has at most one FormResponse,
# holding a history of submissions. The team owns the form (its managers
# manage it); the audience comes from the audience rules.
class Form < ApplicationRecord
  has_neat_id :frm
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :team
  belongs_to :audience_badge, class_name: "Badge", optional: true
  belongs_to :completion_badge, class_name: "Badge", optional: true
  # An event form (a trip permission slip, a "coming Saturday?" poll). Its
  # deadline defaults to the event's start.
  belongs_to :event, optional: true
  belongs_to :created_by, class_name: "Person", optional: true
  has_many :form_questions, -> { order(:position, :created_at) }, dependent: :destroy, inverse_of: :form
  has_many :form_responses, dependent: :destroy
  has_many :form_submissions, through: :form_responses
  has_many :form_reminders, dependent: :destroy
  has_many :form_audience_rules, -> { includes_first }, dependent: :destroy, inverse_of: :form
  has_many :form_badge_grants, dependent: :destroy

  KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

  enum :status, { draft: 0, open: 1, closed: 2, archived: 3 }, validate: true
  enum :respond_permission, AudienceLevels::LEVEL_VALUES, prefix: :respond, validate: true
  enum :read_permission, AudienceLevels::LEVEL_VALUES, prefix: :read, validate: true
  enum :late_entry, { none: 0, leaders: 1 }, prefix: :late_entry, validate: true

  validates :title, presence: true
  validates :key, presence: true, uniqueness: true, format: { with: KEY_FORMAT, message: "must start with a letter and use only lowercase letters, numbers, and underscores" }
  validate :key_unchanged, on: :update
  validate :respond_within_read
  validate :closes_after_opens
  validate :completion_badge_reaches_audience
  validate :event_within_team

  before_validation :generate_key, on: :create
  before_validation -> { self.closes_at ||= event.start_time if event }, if: :will_save_change_to_event_id?
  # The description is part of what respondents read and sign.
  after_update_commit -> { content_changed! }, if: :saved_change_to_description?

  scope :visible, -> { where.not(status: :archived) }
  scope :due_to_open, -> { draft.where(opens_at: ..Time.current).where("closes_at IS NULL OR closes_at > ?", Time.current).where(id: FormAudienceRule.effect_include.select(:form_id)) }
  scope :due_to_close, -> { open.where(closes_at: ..Time.current) }

  def self.ransackable_attributes(auth_object = nil)
    [ "title", "key", "status", "closes_at", "updated_at" ]
  end

  # Opens and closes forms whose dates have passed. Run by FormScheduleJob.
  # A form with no include rule asks nobody, so it stays a draft.
  def self.apply_schedule!
    due_to_open.find_each { |form| form.open! if form.openable? }
    due_to_close.find_each(&:closed!)
  end

  def identifier_name
    title
  end

  def identifier_icon
    "file-signature"
  end

  # Badge rules, the badge filter, badge grants, and the completion badge
  # all wait while Badges are turned off.
  def self.badges_enabled?
    GatherPack::Features.enabled?(:badges)
  end

  # Everyone the form asks: everyone an include rule covers, less everyone an
  # exclude rule covers, narrowed to holders of the audience badge when one
  # is set.
  def audience
    badges = Form.badges_enabled?
    rules = form_audience_rules.to_a
    rules = rules.reject(&:target_badge?) unless badges
    included = rules.select(&:effect_include?)
    return Person.none if included.empty?

    people = AudienceLevels.combine(included.map(&:people))
    excluded = rules.select(&:effect_exclude?)
    people = people.where.not(id: AudienceLevels.combine(excluded.map(&:people)).select(:id)) if excluded.any?
    people = people.where(id: BadgeAssignment.where(badge_id: audience_badge_id).select(:person_id)) if audience_badge_id && badges
    people
  end

  def in_audience?(person)
    audience.where(id: person.id).exists?
  end

  # People with a response who are no longer asked (they left the team, or a
  # rule changed). Their responses are kept and stay readable.
  def former_subjects
    Person.where(id: form_responses.select(:subject_id)).where.not(id: audience.select(:id))
  end

  # Everyone the form asks plus everyone with a response.
  def reachable_subjects
    Person.where(id: audience.select(:id)).or(Person.where(id: form_responses.select(:subject_id)))
  end

  # The people whose responses the viewer may see, as one relation. Must
  # agree with FormAccess#can_read? for every subject.
  def readable_subjects_for(viewer)
    return Person.none if viewer.nil?
    return reachable_subjects if viewer.admin?

    covered = AudienceLevels.combine([ AudienceLevels.people(read_permission, viewer) ] + granted_people(viewer, form_badge_grants))
    covered.where(id: reachable_subjects.select(:id))
  end

  # The people the viewer may fill in a response for, as one relation. Must
  # agree with FormAccess#can_respond?. People no longer asked can only be
  # answered for by their leaders.
  def respondable_subjects_for(viewer)
    return Person.none if viewer.nil?
    return reachable_subjects if viewer.admin?

    level = AudienceLevels.people(respond_permission, viewer)
    grants = granted_people(viewer, form_badge_grants.select(&:respond?))
    asked = AudienceLevels.combine([ level ] + grants).where(id: audience.select(:id))
    former = AudienceLevels.combine([ level.where(id: viewer.all_managed_people.select(:id)) ] + grants).where(id: former_subjects.select(:id))
    asked.or(Person.where(id: former.select(:id)))
  end

  def response_for(subject)
    form_responses.find_by(subject: subject)
  end

  def answerable_questions
    form_questions.select(&:answerable?)
  end

  def signature_questions
    form_questions.select(&:signature?)
  end

  def intent_question
    form_questions.detect(&:intent?)
  end

  # A form asks nobody until it has an include rule.
  def openable?
    form_audience_rules.any? { |rule| rule.effect_include? && (!rule.target_badge? || Form.badges_enabled?) }
  end

  # Whether anyone has submitted answers to this form.
  def answered?
    form_submissions.where.not(submitted_at: nil).exists?
  end

  # Content changes on a form people have already answered start a new
  # content version, so later submissions and signatures record which
  # version they saw. Drafts move to the new version; submissions waiting
  # for signatures go back to draft, and their signatures are revoked,
  # because the text being signed changed. One version covers every change
  # until Publish changes.
  def content_changed!
    return unless persisted? && answered?

    transaction do
      update!(content_version: content_version + 1) if content_version == published_version
      form_submissions.where(status: %i[ draft pending ]).where.not(form_version: content_version).find_each do |submission|
        submission.move_to_version!(content_version)
      end
    end
  end

  def unpublished_changes?
    content_version > published_version
  end

  # Accepts the current content version. With reconfirm, responses whose
  # active submission is on an earlier version need re-confirmation; their
  # answers stay in effect until a new submission replaces them.
  def publish!(reconfirm:)
    transaction do
      update!(published_version: content_version, reconfirm_from_version: reconfirm ? content_version : reconfirm_from_version)
      form_responses.includes(:active_submission).find_each(&:sync_status!) if reconfirm
    end
  end

  # Responses whose active submission has an "updates profile" answer for
  # this field, which may now differ from the profile.
  def self.resync_profile_field!(person, field)
    FormResponse.where(subject: person, form_id: FormQuestion.update_profile.where(person_field: field).select(:form_id))
      .where.not(active_submission_id: nil).find_each(&:sync_status!)
  end

  # Copies the settings and questions, not the responses, as a new draft.
  def duplicate!(title:, key: nil, created_by: nil)
    transaction do
      copy = dup
      copy.assign_attributes(title: title, key: key, status: :draft, content_version: 1, published_version: 1, reconfirm_from_version: 1,
        completion_badge: nil, created_by: created_by, opens_at: nil, closes_at: nil)
      copy.save!
      form_questions.each do |question|
        copy.form_questions.create!(question.attributes.except("id", "form_id", "created_at", "updated_at"))
      end
      form_audience_rules.each do |rule|
        copy.form_audience_rules.create!(rule.attributes.slice("effect", "target_type", "team_id", "badge_id", "person_id", "include_managers"))
      end
      form_badge_grants.each { |grant| copy.form_badge_grants.create!(badge_id: grant.badge_id, access: grant.access) }
      copy
    end
  end

  private

  # The people covered by the grants whose badges the viewer holds.
  def granted_people(viewer, grants)
    return [] unless Form.badges_enabled?

    badge_ids = viewer.badge_ids
    grants.select { |grant| badge_ids.include?(grant.badge_id) }.map(&:covered_people)
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

  # Its managers must manage the event's people, so the event belongs to the
  # owning team or a team below it.
  def event_within_team
    return unless event && team

    if event.team.nil?
      errors.add(:event, "must belong to a team")
    elsif event.team_id != team_id && !team.all_descendant_ids.include?(event.team_id)
      errors.add(:event, "belongs to #{event.team.name}, which isn't #{team.name} or a team below it")
    end
  end

  # Only admins assign the badge, and a team badge can only be held by
  # members of its team, so everyone the include rules cover must be in it.
  def completion_badge_reaches_audience
    return unless completion_badge

    errors.add(:completion_badge, "must be one only admins can assign") unless completion_badge.added_by_admin?
    return unless completion_badge.team
    rule = form_audience_rules.detect { |candidate| candidate.effect_include? && !candidate.within_team?(completion_badge.team) }
    errors.add(:completion_badge, "belongs to #{completion_badge.team.name}, but the form also asks #{rule.description.delete_prefix("Include ")}") if rule
  end
end
