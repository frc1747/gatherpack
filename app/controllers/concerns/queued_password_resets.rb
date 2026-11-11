# Replaces Devise::PasswordsController#create. Devise looks the address up,
# writes a reset token and renders the mail inside the request, but only
# when the address has an account, so the time it takes tells whether it
# does. Here every request queues one job with the address and gets the same
# answer; the job does the rest. See config/initializers/devise_password_reset.rb.
module QueuedPasswordResets
  def create
    fields = params[resource_name]
    email = fields.is_a?(ActionController::Parameters) ? fields[:email].to_s.strip.downcase : ""
    SendResetPasswordInstructionsJob.perform_later(email)

    set_flash_message! :notice, :send_paranoid_instructions
    respond_with({}, location: after_sending_reset_password_instructions_path_for(resource_name))
  end
end
