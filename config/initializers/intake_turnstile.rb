# Cloudflare Turnstile for the public sign-up form (Intake::BotCheck). The
# adapter stays off until both keys are set. The app sets no
# Content-Security-Policy (config/initializers/content_security_policy.rb is
# all comments); if one is enabled it must allow script-src and frame-src
# https://challenges.cloudflare.com.

# The secret is already covered by the :secret filter; the token isn't.
Rails.application.config.filter_parameters += [ "cf-turnstile-response" ]

Rails.application.config.to_prepare do
  Settings.register(:intake_turnstile_site_key, :string, "Turnstile Site Key", "", "Intake",
    "Cloudflare Turnstile site key for the public sign-up form. The check is on only when this and the secret are both set.")
  Settings.register(:intake_turnstile_secret, :string, "Turnstile Secret", "", "Intake",
    "Cloudflare Turnstile secret key. Used only to check answers with Cloudflare.")

  Intake::BotCheck.adapter = Intake::BotCheck::Turnstile.new
end
