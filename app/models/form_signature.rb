# A signature on one submission, for one signature question. It covers the
# submission's content (the form's text as submitted) and its answers,
# through content_digest. Signatures never carry over to a later submission;
# revoking one keeps the row.
class FormSignature < ApplicationRecord
  has_neat_id :frms
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :form_submission
  belongs_to :form_question
  belongs_to :signer, class_name: "Person"
  belongs_to :revoked_by, class_name: "Person", optional: true

  enum :signer_role, { subject: 0, guardian: 1, leader: 2 }, prefix: :signed_as, validate: true

  validates :typed_name, :signed_at, :content_digest, presence: true

  scope :standing, -> { where(revoked_at: nil) }

  def identifier_name
    "#{form_submission&.identifier_name}: signed by #{signer&.identifier_name}"
  end

  def identifier_icon
    "signature"
  end

  def standing?
    revoked_at.nil?
  end

  def revoke!(reason, by: nil)
    update!(revoked_at: Time.current, revoked_reason: reason, revoked_by: by)
  end

  # Whether the submission still has the content and answers this signed.
  def matches?(submission = form_submission)
    content_digest == submission.content_digest
  end
end
