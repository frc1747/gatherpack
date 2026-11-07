# Quietly drops bot submissions of the public sign-up form: a hidden field
# people never fill in (the honeypot), and a signed timestamp from when the
# form was shown, which a person can't beat by much.
module Intake::FormGuard
  HONEYPOT = :website
  MINIMUM_SECONDS = 3

  module_function

  def verifier
    Rails.application.message_verifier("intake-form")
  end

  def stamp(now = Time.current)
    verifier.generate(now.to_f, expires_in: 1.day)
  end

  # Whether the submission looks like a bot's.
  def drop?(params, now = Time.current)
    return true if params[HONEYPOT].present?
    shown_at = verifier.verified(params[:started].to_s)
    shown_at.nil? || now.to_f - shown_at.to_f < MINIMUM_SECONDS
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    true
  end
end
