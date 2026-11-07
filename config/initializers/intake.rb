# Membership intake: registration links and the kiosk, which let people join
# teams without anyone creating their records by hand. The feature keeps its
# settings, hook events and the changes it makes to membership applications
# here rather than in the shared lists and upstream files.

# What people type into a registration stays out of the Rails log. Entries
# hold names, emails and a guardian's details before anyone is verified.
Rails.application.config.filter_parameters += %i[guardian_email email_confirmation token answers facts birth_year]

Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :intake,
      label: "Registration",
      description: "Let people join teams through a registration link or a kiosk",
      default_enabled: false,
      nav_section: "People",
      nav_position: 40,
      nav_items: [
        GatherPack::Feature::NavItem.new(label: "Registrations", path: :intake_registrations_path, icon: "clipboard-list")
      ]
    )
  )

  Settings.register(:intake_kiosk_users_team, :string, "Registration Kiosk: Kiosk Accounts Team", "", "Intake",
    "Name of the team whose members can open a registration kiosk (they must also manage the registration's team). Blank uses the time kiosk's team; if neither is set, any manager of the team can.")
  Settings.register(:intake_domain_hints, :string, "Email Domain Hints", "gmail.com, yahoo.com, outlook.com, hotmail.com, icloud.com, aol.com", "Intake",
    "Comma-separated email domains. An address with a near miss of one gets a \"Did you mean\" hint.")
  Settings.register(:intake_entry_cap, :integer, "Unfinished Sign-ups per Registration", "500", "Intake",
    "When a registration has this many sign-ups waiting for email confirmation, new ones are turned away until some finish or expire.")
  Settings.register(:intake_entry_days, :integer, "Days to Keep Unfinished Sign-ups", "7", "Intake",
    "Sign-ups whose email isn't confirmed are deleted this many days after they start.")
  Settings.register(:intake_link_hours, :integer, "Hours a Confirmation Link Works", "48", "Intake",
    "Links in registration emails stop working after this many hours, and after their first use.")
  Settings.register(:intake_archive_days, :integer, "Hide Registrations Closed For (Days)", "", "Intake",
    "Registrations closed longer than this are left off the list, unless you show archived ones. Blank: never hidden.")
  Settings.register(:intake_idle_seconds, :integer, "Registration Kiosk: Reset After (Seconds)", "60", "Intake",
    "The kiosk clears what was typed after this long with nothing happening.")
  Settings.register(:intake_rate_ip_per_hour, :integer, "Sign-ups per Hour from One Address", "5", "Intake",
    "How many sign-ups one network address can start in an hour.")
  Settings.register(:intake_rate_email_per_hour, :integer, "Sign-ups per Hour for One Email", "3", "Intake",
    "How many sign-ups one email can start in an hour.")
  Settings.register(:intake_rate_registration_per_hour, :integer, "Sign-ups per Hour per Registration", "200", "Intake",
    "How many sign-ups one registration accepts in an hour.")
  Settings.register(:intake_rate_verify_per_hour, :integer, "Confirmation Link Opens per Hour from One Address", "10", "Intake",
    "How many confirmation links one network address can open in an hour.")
  Settings.register(:intake_rate_resend_per_day, :integer, "Resends per Sign-up per Day", "3", "Intake",
    "How many times a day a sign-up's email, or a guardian request, can be sent again (or a guardian or new email named).")
  Settings.register(:intake_rate_household_per_day, :integer, "Family Members Added per Person per Day", "10", "Intake",
    "How many family members one person can add through registrations in a day.")
  Settings.register(:intake_rate_kiosk_per_minute, :integer, "Registration Kiosk: Sign-ups per Minute", "30", "Intake",
    "How many sign-ups one kiosk account can submit in a minute.")

  GatherPack::HookCatalog.register_targets("intake_registrations", "intake_entries")
  GatherPack::HookCatalog.register_events(
    "intake_entries - verified", "intake_entries - expired",
    "membership_applications - submitted", "membership_applications - approved", "membership_applications - denied",
    "intake_registrations - opened", "intake_registrations - closed"
  )

  # Applications carry where they came from and run the registration's
  # placement lists when approved, without editing membership_application.rb.
  # Including a module twice does nothing, so this is safe on every reload.
  MembershipApplication.include(Intake::MembershipApplicationExtension)
  MembershipApplicationsController.include(Intake::ApplicationDecisions)
end
