# Nothing to load: the Turnstile site key and secret are blank by default, so
# the adapter is off and the sign-up form shows no widget (the setup page says
# "No bot check"). Real keys never go in sample data; to try it, an admin sets
# the two "Turnstile" settings under Intake (Cloudflare publishes test keys)
# and restarts the app, since settings are cached per process.
Hbr::SampleData.feature "feature/intake-turnstile" do |s|
  s.note "no data needed (keys stay blank, so the adapter is off)"
end
