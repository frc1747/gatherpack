# Sends password-reset instructions to an email address if it belongs to a
# login. The reset form queues this for every request (see
# QueuedPasswordResets), so the request does the same work whether or not
# the address has an account.
class SendResetPasswordInstructionsJob < ApplicationJob
  queue_as :default

  def perform(email)
    User.send_reset_password_instructions(email: email)
  end
end
