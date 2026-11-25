# The send log of a rule's reminders (Accounting::Reminders): one row per
# reminder about one person to one recipient, keyed by the milestone it was
# about (a rule or plan milestone's id, or "overdue"). It keeps a reminder
# from going twice and spaces overdue ones. Not hookable, and no audit log:
# a send log.
class AccountingReminder < ApplicationRecord
  has_neat_id :arem

  OVERDUE = "overdue".freeze

  belongs_to :rule, class_name: "AccountingRule", inverse_of: :reminders
  belongs_to :person
  belongs_to :recipient, class_name: "Person"

  validates :milestone_key, :sent_at, presence: true
end
