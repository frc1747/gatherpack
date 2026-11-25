# Form expiry on a response (Forms::Expiry): past its expiry, a response
# needs re-confirmation for the reason :expired. It counts from the moment
# it expires: a response stored as complete reads as needing
# re-confirmation (#status, #complete?) until FormExpiryJob stores that,
# which also removes the completion badge and runs the incomplete hooks.
module Forms::ResponseExpiry
  def self.prepended(base)
    # Complete responses whose expiry has passed: their form's date, or
    # their active submission's activation plus the form's months.
    base.scope :past_expiry, ->(now = Time.current) {
      complete.joins(:form, :active_submission)
        .where("forms.expires_on <= :today OR form_submissions.activated_at + forms.valid_for_months * interval '1 month' <= :now",
          today: now.in_time_zone.to_date, now: now)
    }
  end

  # When the active submission stops counting, or nil if it doesn't expire.
  def expires_at
    return unless form&.expires? && (submission = signed_submission)&.active?

    form.expiry_for(submission.activated_at)
  end

  def expired?(now = Time.current)
    (at = expires_at).present? && at <= now
  end

  # Expiry comes first: whatever else changed, the answers no longer count.
  def reconfirmation_reason
    expired? ? :expired : super
  end

  def status
    expired_unstored? ? "needs_reconfirmation" : super
  end

  def complete?
    !expired_unstored? && super
  end

  def needs_reconfirmation?
    expired_unstored? || super
  end

  # "Good until <date>" while the active submission counts and has an
  # expiry, "Expired <date>" once it has passed, nil if it doesn't expire.
  # The date is the last day it counts.
  def expiry_summary
    return unless (at = expires_at)

    expired? ? "Expired #{at.strftime("%B %-d, %Y")}" : "Good until #{(at - 1.second).strftime("%B %-d, %Y")}"
  end

  private

  # Stored as complete, but past its expiry: the job hasn't run yet.
  def expired_unstored?
    read_attribute(:status) == "complete" && expired?
  end

  # The active submission, from the loaded submissions when a list (the
  # form's report) has them, so rows don't each query for it.
  def signed_submission
    return active_submission if association(:active_submission).loaded? || !association(:form_submissions).loaded?

    form_submissions.detect { |submission| submission.id == active_submission_id }
  end
end
