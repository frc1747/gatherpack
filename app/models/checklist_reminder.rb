# A log of one reminder send for a checklist, by hand (Send Reminder) or on
# its schedule: who sent it, when and to how many. Counts only: the emails
# themselves aren't kept.
class ChecklistReminder < ApplicationRecord
  has_neat_id :chkrm

  CREATED_EVENT = "checklist_reminders - created".freeze

  belongs_to :checklist
  belongs_to :sent_by, class_name: "Person", optional: true

  validates :sent_at, presence: true

  scope :scheduled, -> { where(scheduled: true) }

  after_create_commit :run_created_hooks

  # Reminders are on: the feature_checklist_reminders flag and checklists.
  def self.enabled?
    Checklists.enabled? && GatherPack::Features.enabled?(:checklist_reminders)
  end

  def identifier_name
    "#{checklist&.title} reminder #{sent_at&.to_date}"
  end

  def identifier_icon
    "paper-plane"
  end

  private

  def run_created_hooks
    Hook.where(event: CREATED_EVENT).each { |hook| hook.run(self) }
  end
end
