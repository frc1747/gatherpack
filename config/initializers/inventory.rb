# Inventory: the feature switch, settings, menu section, hook events and
# the reorder actions inventory offers itself. Uses config.to_prepare (like
# features.rb) so the registrations are replayed after each development
# reload.
Rails.application.config.to_prepare do
  # A shared section for anything that buys or keeps things; registering it
  # again from another feature is harmless. Inventory::Feature uses it when
  # another enabled feature has entries there, and its own section otherwise.
  GatherPack::Features.register_section("Purchasing", position: 35)
  GatherPack::Features.register_section("Inventory", position: 35)

  # Reorder, Items, Places and Changes are for inventory managers. They go
  # in the menu only where a menu entry can be hidden per person; elsewhere
  # the Inventory pages link to them (Inventory.manager_pages).
  manager_items =
    if GatherPack::Feature::NavItem.members.include?(:visible)
      Inventory::MANAGER_PAGES.map do |label, path, icon|
        GatherPack::Feature::NavItem.new(label: label, path: path, icon: icon,
          visible: ->(user) { Inventory::Access.for(user&.person).manager? })
      end
    else
      []
    end

  GatherPack::Features.register(
    Inventory::Feature.new(
      key: :inventory,
      label: "Inventory",
      description: "Items, places and stock: what there is, where it is, and when to buy more",
      default_enabled: false,
      nav_position: 50,
      nav_items: [
        GatherPack::Feature::NavItem.new(label: "Inventory", path: :inventory_root_path, icon: "boxes-stacked")
      ] + manager_items
    )
  )

  Settings.register(:inventory_users, :text, "Who Can Use Inventory", "", "Inventory",
    "Teams whose members (and members of the teams below) may see and record stock, one team name per line. " \
    "Blank: everyone signed in")
  Settings.register(:inventory_managers, :text, "Inventory Managers", "", "Inventory",
    "Who manages items and places without managing a team. One per line, as Badge name > Highest team name, " \
    "as for sign-up organizers. Admins and team managers always can")
  Settings.register(:inventory_member_kinds, :string, "What Members Can Record",
    Inventory::Config::DEFAULT_MEMBER_KINDS.join(", "), "Inventory",
    "Changes members may record, separated by commas, from: used, moved, counted, received, added, removed. " \
    "Inventory managers may record every kind")
  Settings.register(:inventory_member_unit_actions, :string, "What Members Can Do With Units",
    Inventory::Config::DEFAULT_MEMBER_UNIT_ACTIONS.join(", "), "Inventory",
    "Actions members may take on tracked units, separated by commas, from: install, take off, move, check, " \
    "mark for repair, repaired, retire. Inventory managers may take every action")
  Settings.register(:inventory_used_needs_reason, :boolean, "Used Needs a Reason", "false", "Inventory",
    "Recording Used asks \"What for?\" and needs an answer")
  Settings.register(:inventory_undo_minutes, :integer, "Undo Minutes", Inventory::Config::DEFAULT_UNDO_MINUTES.to_s, "Inventory",
    "How long the person who recorded a change can undo it. Inventory managers can undo any change at any time")
  Settings.register(:inventory_reorder_notice, :string, "Running Low Notices", "daily", "Inventory",
    "When inventory managers hear that an item is running low: off, each (an email each time) or daily (in the daily digest)")
  Settings.register(:inventory_default_unit, :string, "Default Stock Unit", "each", "Inventory",
    "The stock unit a new item starts with")

  GatherPack::HookCatalog.register_targets(*Inventory::HOOK_TARGETS)
  GatherPack::HookCatalog.register_events(*Inventory::HOOK_EVENTS)

  # The reorder list's own actions on ticked items: Print and Download CSV.
  routes = Rails.application.routes.url_helpers
  ticked = ->(rows) { rows.to_h { |item, quantity| [ item.id, quantity ] } }
  Inventory.extensions.register_reorder_action(:print, label: "Print",
    path: ->(rows) { routes.inventory_reorder_path(print: 1, items: ticked.call(rows)) })
  Inventory.extensions.register_reorder_action(:csv, label: "Download CSV",
    path: ->(rows) { routes.inventory_reorder_path(format: :csv, items: ticked.call(rows)) })
end
