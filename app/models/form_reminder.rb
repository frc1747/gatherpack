# A log of one press of Remind on a form's status page.
class FormReminder < ApplicationRecord
  has_neat_id :frmrm
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :form
  belongs_to :sent_by, class_name: "Person", optional: true

  validates :sent_at, presence: true

  def identifier_name
    "#{form&.title} reminder #{sent_at&.to_date}"
  end
end
