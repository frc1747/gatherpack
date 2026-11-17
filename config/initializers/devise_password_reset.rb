# Password-reset requests are answered the same way and in the same time
# whether or not the address has an account (see QueuedPasswordResets).
Rails.application.config.to_prepare do
  Devise::PasswordsController.prepend QueuedPasswordResets
end
