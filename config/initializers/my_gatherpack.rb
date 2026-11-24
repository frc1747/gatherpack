# Pins on the sidebar. Appended here so the routes come with this file; the
# controller turns people away while the feature is off.
Rails.application.routes.append do
  resources :menu_pins, only: %i[create destroy]
end

Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :my_gatherpack,
      label: "My GatherPack",
      description: "A short menu of what each person uses, with management tools set apart",
      default_enabled: false,
      nav_section: "People",
      nav_items: [
        GatherPack::Feature::NavItem.new(label: "Family", path: :family_path, icon: "children",
          visible: ->(user) { FamilyPolicy.new(user, :family).show? })
      ]
    )
  )

  GatherPack::ViewOverrides.register(
    :my_gatherpack,
    path: Rails.root.join("app/view_overrides/my_gatherpack"),
    position: 20,
    active: ->(_controller) { MyGatherpack.enabled? }
  )

  MyGatherpack.register_section(:events, partial: "my_gatherpack/event_row", column: :coming_up, position: 10,
    enabled: -> { GatherPack::Features.enabled?(:events) }, items: -> { my_gatherpack_event_items })
  # After the checklist season (20) and the activity section (20.5), which sit under My Season.
  MyGatherpack.register_section(:right_widgets, partial: "my_gatherpack/right_widgets", column: :side, position: 25)
  MyGatherpack.register_section(:announcements, partial: "my_gatherpack/announcements", column: :side, position: 30)

  GatherPack::SidebarSlots.fingerprint(:my_gatherpack) { my_gatherpack_sidebar_fingerprint }

  # Where each nav item goes, by path helper. Anything else goes under its
  # section heading. +part+ is the Manage part an item is listed in
  # (MyGatherpack::Menu::PARTS). Items from features not in this build are
  # ignored until they are.
  MyGatherpack::Menu.table = {
    signup_sheets_path: { top: 10 },
    forms_path: { top: 20 },
    checklists_path: { top: 30 },
    time_clock_punches_path: { top: 40, manage: 70, part: :time },
    calendar_index_path: { top: 50 },
    teams_path: { top: 60, manage: 20, part: :people },
    announcements_path: { top: 70 },
    family_path: { family: 10 },
    people_path: { manage: 10, part: :people },
    badges_path: { manage: 30, part: :people },
    tokens_path: { manage: 40, part: :people },
    commitments_path: { manage: 50, part: :people },
    intake_registrations_path: { manage: 60, part: :people },
    ledgers_path: { manage: 80, part: :money },
    budgets_path: { manage: 90, part: :money },
    pages_path: { manage: 100, part: :content },
    widgets_path: { manage: 110, part: :content },
    mailboxes_path: { manage: 120, part: :content },
    shortcuts_path: { manage: 130, part: :content }
  }

  # Report Pages are ticked into the menu on the Page form, and take their
  # pins with them when deleted.
  Page.include(MyGatherpack::PageMenuPins)
  PagesController.prepend(MyGatherpack::PageMenuParams)
end
