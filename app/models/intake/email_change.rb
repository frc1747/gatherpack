# "Change email" after joining: the new address is confirmed before the
# login changes. The link carries a signed, expiring message naming the
# login, its email then and the new one, so it works only until the email
# changes (once) and for intake_link_hours. Nothing is stored until then.
module Intake::EmailChange
  PURPOSE = :intake_email_change

  module_function

  def verifier
    Rails.application.message_verifier("intake-email-change")
  end

  def token(user, new_email)
    verifier.generate({ "user_id" => user.id, "from" => user.email, "to" => Intake.normalize_email(new_email) },
      purpose: PURPOSE, expires_in: Intake.setting(:intake_link_hours, 48).hours)
  end

  # [user, new email] for a link that can still be used, or nil.
  def resolve(token)
    data = verifier.verified(token.to_s, purpose: PURPOSE)
    return unless data.is_a?(Hash)
    user = User.find_by(id: data["user_id"])
    return unless user && user.email == data["from"]
    return if Intake.user_for_email(data["to"])
    [ user, data["to"] ]
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def apply!(token)
    user, new_email = resolve(token)
    return unless user
    user.update!(email: new_email, intake_login_verified_at: Time.current) && user
  end
end
