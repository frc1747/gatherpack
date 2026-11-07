# Checklists' feature switch, settings, hook events, item kinds and the
# patches it makes to other models. Uses config.to_prepare (like
# features.rb) so the kind registry, which lives in reloadable app/ code, is
# filled again after each development reload.
#
# Another branch adds an item kind from its own initializer:
#
#   Rails.application.config.to_prepare do
#     next unless defined?(Checklists) && Checklists.respond_to?(:register_item_kind)
#
#     Checklists.register_item_kind(:count, Checklists::Kinds::Count)
#   end
Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :checklists,
      label: "Checklists",
      description: "Lists of what people must have, do or be, with each person's progress",
      default_enabled: false,
      nav_section: "People",
      nav_position: 26,
      nav_items: [
        GatherPack::Feature::NavItem.new(label: "Checklists", path: :checklists_path, icon: "list-check")
      ],
      # Shown when the viewer may see at least one of the person's checklists.
      profile_tabs: [
        GatherPack::Feature::ProfileTab.new(
          label: "Checklists",
          path: ->(person) { person_checklists_path(person) },
          visible: ->(user, person) { user.person.present? && Checklists.checklist_for(person, viewer: user.person).any? }
        )
      ]
    )
  )

  Settings.register(:checklists_organizers, :text, "Checklist Organizers", "", "Checklists",
    "Who may make and run checklists without managing a team. One per line, as Badge name > Highest team name. " \
    "Holders of the badge (one only admins give) can run checklists for the teams they belong to at or below that team, " \
    "and the teams below their own. Leave out \"> Highest team name\" to allow only the teams they're directly in and the teams below those")
  Settings.register(:checklists_max_age_hours, :integer, "Checklist Results Max Age (hours)", "24", "Checklists",
    "Stored results older than this are recomputed when read")
  Settings.register(:checklists_archive_after, :string, "Archive Checklists Ended Before (old)", "", "Checklists",
    "Replaced by Archive Checklists Automatically (days) under Housekeeping, and read only while that is blank. " \
    "A date (YYYY-MM-DD), or a number of days after a checklist's end")
  Settings.register(:checklists_prune_results_after, :string, "Clear Results of Archived Checklists Ended Before", "", "Checklists",
    "A date (YYYY-MM-DD), or a number of days after a checklist's end. Stored results of archived checklists that ended before it are cleared each night; recorded lists stay. Blank: never")

  GatherPack::HookCatalog.register_targets(*Checklists::HOOK_TARGETS)
  GatherPack::HookCatalog.register_events(Checklists::STATUS_CHANGED_EVENT)

  Checklists.register_item_kind(:badge, Checklists::Kinds::Badge)
  Checklists.register_item_kind(:team_member, Checklists::Kinds::TeamMember)
  Checklists.register_item_kind(:has_login, Checklists::Kinds::HasLogin)
  Checklists.register_item_kind(:age, Checklists::Kinds::Age)
  Checklists.register_item_kind(:attested, Checklists::Kinds::Attested)
  Checklists.register_item_kind(:checklist, Checklists::Kinds::Checklist)
  Checklists.register_item_kind(:any_of, Checklists::Kinds::AnyOf)
  Checklists::Invalidation.install_population

  # A checklist's team, and the teams and badges its rules and grants name,
  # can't be deleted while they're used (a readable error; the foreign keys
  # block it too).
  Checklists::ProtectsReferences.install_model(Team)
  Checklists::ProtectsReferences.install_model(Badge)
end
