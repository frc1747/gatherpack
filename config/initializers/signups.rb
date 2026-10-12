# Sign-up sheets keep their setting and hook events here rather than in the
# shared lists in lib/settings.rb and Hook.catalog.
Rails.application.config.to_prepare do
  Settings.register(:signups_organizers, :text, "Sign-up Sheet Organizers", "", "Sign-ups", "Who may create and run sign-up sheets without managing a team. One per line, as Badge name > Highest team name. Holders of the badge (one only admins assign) can run sheets for the teams they belong to at or below that team, and the teams below their own. Leave out \"> Highest team name\" to allow only the teams they're directly in and the teams below those")

  GatherPack::HookCatalog.register_targets(
    "signup_sheets", "signup_sheet_organizers", "signup_audience_rules", "signup_sheet_events",
    "signup_positions", "signup_position_rules", "signup_slots", "signups"
  )
  GatherPack::HookCatalog.register_events("signups - fulfilled", "signups - cancelled")

  # Check-ins fulfil sign-ups, and event time changes reach the people
  # signed up, without editing checkin.rb or event.rb (decision 7). These
  # run on every reload in development, against the freshly loaded classes;
  # including a module twice does nothing.
  Checkin.include(Signups::CheckinFulfilment)
  Event.include(Signups::EventChanges)
end
