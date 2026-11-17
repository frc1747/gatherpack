# Sends the link that confirms a new login email. The link is a signed,
# expiring message naming the login, its current email and the new one, so
# it stops working once the email changes; it is made here, not queued.
class Intake::EmailChangeJob < ApplicationJob
  queue_as :default

  def perform(user_id, new_email)
    user = User.find_by(id: user_id)
    return unless user
    Intake::Notices.confirm_email_change(user, new_email, Intake::EmailChange.token(user, new_email))
  end
end
