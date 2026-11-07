# Form expiry on a response (Forms::Expiry): past its expiry, a response
# needs re-confirmation for the reason :expired. Computed when read, so a
# response never shows as complete past its expiry; FormExpiryJob stores
# the status, which removes the completion badge and runs the incomplete
# hooks.
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
    form.expiry_for(active_submission.activated_at) if active_submission&.active?
  end

  def expired?(now = Time.current)
    (at = expires_at).present? && at <= now
  end

  # Expiry comes first: whatever else changed, the answers no longer count.
  def reconfirmation_reason
    expired? ? :expired : super
  end

  # "Good until <date>" while the active submission counts and has an
  # expiry, "Expired <date>" once it has passed, nil if it doesn't expire.
  # The date is the last day it counts.
  def expiry_summary
    return unless (at = expires_at)

    expired? ? "Expired #{at.strftime("%B %-d, %Y")}" : "Good until #{(at - 1.second).strftime("%B %-d, %Y")}"
  end
end
