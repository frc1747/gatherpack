Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :my_gatherpack,
      label: "My GatherPack",
      description: "A short menu of what each person uses, with management tools set apart",
      default_enabled: false
    )
  )

  GatherPack::ViewOverrides.register(
    :my_gatherpack,
    path: Rails.root.join("app/view_overrides/my_gatherpack"),
    position: 20,
    active: ->(_controller) { MyGatherpack.enabled? }
  )

  GatherPack::SidebarSlots.fingerprint(:my_gatherpack) { my_gatherpack_sidebar_fingerprint }

  # Where each nav item goes, by path helper. Anything else lands in More.
  MyGatherpack::Menu.table = {
    forms_path: { top: 10 },
    signup_sheets_path: { top: 20 },
    time_clock_punches_path: { top: 30, manage: 30 },
    calendar_index_path: { top: 40 },
    teams_path: { top: 50, manage: 20 },
    announcements_path: { top: 60 },
    family_path: { family: 10 },
    people_path: { manage: 10 },
    badges_path: { manage: 40 },
    tokens_path: { manage: 50 },
    commitments_path: { manage: 60 },
    ledgers_path: { manage: 70 },
    budgets_path: { manage: 80 },
    mailboxes_path: { manage: 90 },
    pages_path: { manage: 100 },
    widgets_path: { manage: 110 }
  }
end
