# One kind of activity counting toward a commitment (spec §4.2): a
# registered kind, its subject, and a ratio (per records' quantity earns
# credits) with an optional cap per person. Sources are ordered; with
# dedupe, the first source to credit a person for an event wins.
class CommitmentSource < ApplicationRecord
  has_neat_id :cmsr
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :commitment
  belongs_to :subject, polymorphic: true, optional: true

  validates :kind, presence: true
  validates :per, numericality: { only_integer: true, greater_than: 0 }
  validates :credits, numericality: { only_integer: true, greater_than: 0 }
  validates :max_credits, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :position, numericality: { only_integer: true }
  validate :kind_registered, if: -> { new_record? || will_save_change_to_kind? }
  validate :subject_matches_kind, if: :kind_class

  before_validation :set_position, on: :create

  def identifier_name
    "#{commitment&.title}: #{label}"
  end

  # The registered kind's class, or nil when its branch isn't in the build.
  def kind_class
    Commitments.source_kind(kind)
  end

  def available?
    kind_class.present?
  end

  def kind_instance
    kind_class&.new(self)
  end

  def label
    return "#{kind.to_s.humanize} (unavailable)" unless available?

    [ kind_class.label, subject_name ].compact_blank.join(": ")
  end

  def subject_name
    subject.try(:identifier_name) || subject.try(:name)
  end

  # floor(quantity × credits / per), capped at max_credits.
  def credit_for(quantity)
    [ quantity * credits / per, max_credits ].compact.min
  end

  def capped?(quantity)
    max_credits.present? && quantity * credits / per >= max_credits
  end

  def ratio_text
    return "Each counts as #{credits}" if per == 1 && credits != 1
    return "Each counts as 1" if per == 1

    "#{per} count as #{credits}"
  end

  private

  def kind_registered
    errors.add(:kind, "isn't available") unless available?
  end

  def subject_matches_kind
    errors.add(:subject, "must be chosen") if subject.nil? || subject_type != kind_class.subject_type
  end

  def set_position
    self.position ||= 0
    return unless commitment && position.zero?

    self.position = (commitment.commitment_sources.where.not(id: id).maximum(:position) || 0) + 1
  end
end
