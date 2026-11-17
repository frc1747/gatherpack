# A manager's or admin's reasoned exception for one person on one item
# (spec §7): the item becomes exempt, labelled "Excused". event_id narrows
# it to one meeting, for kinds that count events. Nobody excuses
# themselves or a relative.
class ChecklistExcuse < ApplicationRecord
  has_neat_id :chlx
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  SELF_REASON = "Another manager needs to excuse you or a relative".freeze

  belongs_to :item, class_name: "ChecklistItem", inverse_of: :checklist_excuses
  belongs_to :person
  belongs_to :event, optional: true
  belongs_to :created_by, class_name: "Person", optional: true

  validates :reason, presence: true
  validates :created_by, presence: true, on: :create
  validate :excused_by_manager, on: :create

  scope :whole_item, -> { where(event_id: nil) }
  scope :in_force, ->(date) { where(expires_on: nil).or(where(expires_on: date..)) }

  after_commit :refresh_person

  def identifier_name
    "#{item&.label}: #{person&.display_name}"
  end

  # Whether the person may excuse the subject on this checklist.
  def self.allowed?(checklist, by, subject)
    checklist.manager?(by) && by.id != subject.id && !Checklists.related?(by, subject)
  end

  private

  def excused_by_manager
    return if item.nil? || person.nil? || created_by.nil?
    return errors.add(:base, SELF_REASON) if created_by.id == person.id || Checklists.related?(created_by, person)

    errors.add(:base, "Only managers of #{item.checklist.team.name} and admins can excuse") unless item.checklist.manager?(created_by)
  end

  def refresh_person
    return unless Checklists.enabled?

    checklist = Checklist.find_by(id: item&.checklist_id)
    Checklists.mark(checklist, [ person_id ]) if checklist && !checklist.archived?
  end
end
