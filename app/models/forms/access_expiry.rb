# A response past its form's expiry can be updated even when updates are
# off, as any response needing re-confirmation can, before FormExpiryJob
# stores its status.
module Forms::AccessExpiry
  private

  def response_needs_reconfirmation?
    super || form.form_responses.find_by(subject: subject)&.needs_reconfirmation? || false
  end
end
