# Limits on Devise's sign-in, password reset, unlock and sign-up forms (see
# AuthenticationRateLimits). Lockable separately locks an account after
# Devise.maximum_attempts wrong passwords.
Rails.application.config.to_prepare do
  # Declared once per class, or a second run without a class reload would count
  # each attempt twice.
  next if Devise::SessionsController < AuthenticationRateLimits

  {
    Devise::SessionsController => { per_ip: { to: 20, within: 3.minutes }, per_email: { to: 10, within: 15.minutes } },
    Devise::PasswordsController => { per_ip: { to: 10, within: 15.minutes }, per_email: { to: 5, within: 15.minutes } },
    Devise::UnlocksController => { per_ip: { to: 10, within: 15.minutes }, per_email: { to: 5, within: 15.minutes } },
    Devise::RegistrationsController => { per_ip: { to: 10, within: 15.minutes }, per_email: { to: 5, within: 15.minutes } }
  }.each do |controller, limits|
    controller.include AuthenticationRateLimits
    controller.rate_limit_authentication(**limits)
  end

  # Editing one's account there takes the current password.
  Devise::RegistrationsController.rate_limit_current_password
end
