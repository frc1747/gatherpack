# One item on a form. Inputs are answered; headings and statements are only
# shown. An input either has its own type (form only) or takes its type from
# a person field, in which case it's filled in from the profile (prefill) or
# also saves the answer to the profile when a submission becomes active
# (update_profile). Every answer is kept on the submission either way.
# Acknowledgments are yes/no answers that must be ticked when required.
# Signatures aren't answers: they're FormSignature rows, given after
# submitting, by the person `signer` names.
class FormQuestion < ApplicationRecord
  has_neat_id :frmq
  include FieldValueType
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :form, inverse_of: :form_questions
  belongs_to :person_field, optional: true

  KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

  # Changing any of these on an answered form changes what respondents see
  # and sign, so it starts a new form content version (Form#content_changed!).
  CONTENT_ATTRIBUTES = %w[ kind label body data_type options person_field_id profile_mode required signer ].freeze

  enum :kind, { input: 0, heading: 1, statement: 2, acknowledgment: 3, signature: 4, intent: 5 }, validate: true
  enum :profile_mode, { prefill: 0, update_profile: 1 }, validate: { allow_nil: true }
  enum :read_permission, AudienceLevels::LEVEL_VALUES, prefix: :read, validate: { allow_nil: true }
  enum :write_permission, AudienceLevels::LEVEL_VALUES, prefix: :write, validate: { allow_nil: true }
  enum :signer, { subject: 0, guardian: 1, guardian_if_minor: 2, leader: 3 }, prefix: :signed_by, validate: { allow_nil: true }

  validates :label, presence: true, if: -> { answerable? || signature? }
  validates :signer, presence: true, if: :signature?
  validates :body, presence: true, if: -> { statement? || (heading? && label.blank?) }
  validates :key, presence: true, uniqueness: { scope: :form_id }, format: { with: KEY_FORMAT, message: "must start with a letter and use only lowercase letters, numbers, and underscores" }
  validate :key_unchanged, on: :update
  validate :profile_link_makes_sense
  validate :levels_within_form
  validate :signer_can_see_form

  before_validation :generate_key, on: :create
  before_validation :clear_unused_attributes

  # One callback: Rails keeps only the last of several *_commit callbacks
  # naming the same method.
  after_commit :note_content_change

  def self.ransackable_attributes(auth_object = nil)
    [ "label", "key", "updated_at" ]
  end

  def identifier_name
    "#{form&.title} / #{label.presence || key}"
  end

  def answerable?
    input? || acknowledgment? || intent?
  end

  def profile_backed?
    person_field_id.present?
  end

  def form_only?
    !profile_backed?
  end

  # Who signs, in words: "a guardian", "the person themselves".
  def signer_description
    {
      "subject" => "the person themselves", "guardian" => "a guardian",
      "guardian_if_minor" => "a guardian (or the person themselves if they have none)", "leader" => "a leader, recording a paper signature"
    }[signer]
  end

  # What a signature or submission covers of this question.
  def content_snapshot
    snapshot = { "key" => key, "kind" => kind, "label" => label, "body" => body, "required" => required? }
    snapshot["signer"] = signer if signature?
    if input?
      snapshot["type"] = value_type.data_type
      snapshot["choices"] = value_type.choice_list if %w[ select multi_select ].include?(value_type.data_type)
      snapshot["person_field"] = person_field.key if profile_backed?
      snapshot["profile_mode"] = profile_mode if profile_backed?
    end
    snapshot.compact
  end

  # The type definition answers follow: the person field's, or the question's
  # own.
  def value_type
    profile_backed? ? person_field : self
  end

  def effective_read_permission
    read_permission || form.read_permission
  end

  def effective_write_permission
    write_permission || form.respond_permission
  end

  # Stored answer (a JSON value in the submission's answers) -> Ruby value.
  def cast_answer(stored)
    value_type.cast(stored.nil? ? nil : stored.to_json)
  end

  # Ruby value -> stored answer. nil means "no answer".
  def store_answer(value)
    serialized = value_type.serialize(value)
    serialized && JSON.parse(serialized)
  end

  def normalize_answer(input, current: nil)
    value_type.normalize(input, current: current)
  end

  # Whether a stored answer counts as no answer. An unticked yes/no is stored
  # as no answer, so a required one must be ticked.
  def blank_answer?(stored)
    stored.nil? || stored == [] || stored == ""
  end

  # Swaps this question with its neighbour.
  def move(direction)
    siblings = form.form_questions.to_a
    index = siblings.index(self)
    other = direction.to_s == "up" ? index - 1 : index + 1
    return if other.negative? || other >= siblings.size

    siblings[index], siblings[other] = siblings[other], siblings[index]
    transaction do
      siblings.each_with_index { |question, position| question.update!(position: position) if question.position != position }
    end
  end

  private

  def generate_key
    return if key.present?

    source = label.presence || body.to_s.truncate(30, omission: "").presence || kind
    base = source.delete("'’").parameterize(separator: "_").gsub(/[^a-z0-9]+/, "_").sub(/\A[^a-z]+/, "").delete_suffix("_").presence || "question"
    taken = form ? form.form_questions.where.not(id: id).pluck(:key) : []
    candidate = base
    suffix = 1
    candidate = "#{base}_#{suffix += 1}" while taken.include?(candidate)
    self.key = candidate
  end

  def clear_unused_attributes
    self.signer = nil unless signature?
    if signature?
      # Signatures are always required, and who signs comes from `signer`.
      self.required = true
      self.read_permission = nil
      self.write_permission = nil
    end
    unless input?
      self.person_field_id = nil
      self.profile_mode = nil
    end
    self.profile_mode = nil if person_field_id.blank?
    self.data_type = "boolean" if acknowledgment?
    # Profile-backed questions take their type from the person field.
    self.options = {} if profile_backed? || !input?
    self.read_permission = nil if heading? || statement?
    self.write_permission = nil if heading? || statement?
  end

  # FieldValueType checks choices for select types; profile-backed and
  # display-only questions have none of their own.
  def options_make_sense
    super if input? && form_only?
  end

  # Without this the signature could never be given: signers must be able
  # to see the response they sign.
  def signer_can_see_form
    return unless signature? && signer && form&.read_permission

    component = { "subject" => :subject, "guardian" => :guardian, "guardian_if_minor" => :guardian, "leader" => :leaders }.fetch(signer)
    return if AudienceLevels.reaches?(form.read_permission, component) && (signer != "guardian_if_minor" || AudienceLevels.reaches?(form.read_permission, :subject))

    errors.add(:signer, "can't see this form's responses; change who can see them first")
  end

  def note_content_change
    return if destroyed_by_association
    return unless destroyed? || previously_new_record? || (saved_changes.keys & CONTENT_ATTRIBUTES).any?

    form&.content_changed!
  end

  def key_unchanged
    errors.add(:key, "can't be changed once created") if will_save_change_to_key?
  end

  def profile_link_makes_sense
    return unless profile_backed?

    errors.add(:profile_mode, "can't be blank") if profile_mode.nil?
    errors.add(:person_field, "is archived") if person_field.archived?
    errors.add(:person_field, "is managed by account settings and can't be updated from a form") if update_profile? && person_field.system_read_only?
  end

  # A question can be more private than its form, never more public; and
  # writing can't reach further than reading or than the form's respond level.
  def levels_within_form
    return unless form&.read_permission && form&.respond_permission

    if read_permission && !AudienceLevels.within?(read_permission, form.read_permission)
      errors.add(:read_permission, "can't include people who can't see the form's answers")
    end
    if write_permission && !AudienceLevels.within?(write_permission, effective_read_permission)
      errors.add(:write_permission, "can't include people who can't see this question")
    end
    if write_permission && !AudienceLevels.within?(write_permission, form.respond_permission)
      errors.add(:write_permission, "can't include people who can't answer the form")
    end
  end
end
