# Inventory: the feature switch, settings, menu section, hook events and
# the reorder actions inventory offers itself. Uses config.to_prepare (like
# features.rb) so the registrations are replayed after each development
# reload.
Rails.application.config.to_prepare do
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

  # Setup is a button on the main Setup page, for admins, not a menu item.
  setup_item = GatherPack::Feature::SetupItem.new(label: "Inventory", path: :inventory_setup_path,
    policy_check: ->(view) { view.current_user&.admin })

  GatherPack::Features.register(
    Inventory::Feature.new(
      key: :inventory,
      label: "Inventory",
      description: "Items, places and stock: what there is, where it is, and when to buy more",
      default_enabled: false,
      nav_position: 50,
      nav_items: [
        GatherPack::Feature::NavItem.new(label: "Stock", path: :inventory_stock_path, icon: "boxes-stacked"),
        # Named and shown as Inventory setup says (Inventory::Feature#nav_items).
        GatherPack::Feature::NavItem.new(label: "Machines", path: :inventory_machines_path, icon: Inventory::MACHINE_ICON)
      ] + manager_items,
      setup_section: "Inventory",
      setup_items: [ setup_item ]
    )
  )

  # Where the settings pickers aren't there, the settings stay text boxes
  # and their descriptions say what to type.
  picked = Settings.respond_to?(:input)
  Settings.register(:inventory_users, :text, "Who Can Use Inventory", "", "Inventory",
    if picked
      "Members of these teams, and of the teams below them, may see and record stock. " \
        "None picked: everyone signed in"
    else
      "Teams whose members (and members of the teams below) may see and record stock, one team name per line. " \
        "Blank: everyone signed in"
    end)
  Settings.register(:inventory_managers, :text, "Inventory Managers", "", "Inventory",
    if picked
      "Who manages items and places without managing a team, by badge: for the team picked and the teams " \
        "below it, or every team when none is picked. Admins and team managers always can"
    else
      "Who manages items and places without managing a team. One per line, as Badge name > Team name: " \
        "for that team and the teams below it. Blank team: every team. Admins and team managers always can"
    end)
  Settings.register(:inventory_member_kinds, :string, "What Members Can Record",
    Inventory::Config::DEFAULT_MEMBER_KINDS.join(", "), "Inventory",
    if picked
      "The changes members may record. Inventory managers may record every kind"
    else
      "Changes members may record, separated by commas, from: used, moved, counted, received, added, removed. " \
        "Inventory managers may record every kind"
    end)
  Settings.register(:inventory_member_unit_actions, :string, "What Members Can Do With Units",
    Inventory::Config::DEFAULT_MEMBER_UNIT_ACTIONS.join(", "), "Inventory",
    if picked
      "The actions members may take on tracked units. Inventory managers may take every action"
    else
      "Actions members may take on tracked units, separated by commas, from: install, take off, move, check, " \
        "mark for repair, repaired, retire. Inventory managers may take every action"
    end)
  Settings.register(:inventory_used_needs_reason, :boolean, "Used Needs a Reason", "false", "Inventory",
    "Recording Used asks \"What for?\" and needs an answer")
  Settings.register(:inventory_undo_minutes, :integer, "Undo Minutes", Inventory::Config::DEFAULT_UNDO_MINUTES.to_s, "Inventory",
    "How long the person who recorded a change can undo it. Inventory managers can undo any change at any time")
  Settings.register(:inventory_reorder_notice, :string, "Running Low Notices", "daily", "Inventory",
    if picked
      "When inventory managers hear that an item is running low"
    else
      "When inventory managers hear that an item is running low: off, each (an email each time), daily (in the daily digest) " \
        "or weekly (in the Weekly Infodump, when Summaries is on)"
    end)
  Settings.register(:inventory_default_unit, :string, "Default Stock Unit", "each", "Inventory",
    "The stock unit a new item starts with")
  Settings.register(:inventory_machines, :string, "Things Parts Get Installed On", "on", "Inventory",
    if picked
      "Places that are built and run, with tracked parts installed on them, each with its own page"
    else
      "Places that are built and run, with tracked parts installed on them, each with its own page: on or off"
    end)
  Settings.register(:inventory_machine_name, :string, "What One Is Called", "", "Inventory",
    "The name for one of them, such as Robot, Project or Tool. Blank: #{Inventory::Config::DEFAULT_MACHINE_NAME}")
  Settings.register(:inventory_machine_name_plural, :string, "What Several Are Called", "", "Inventory",
    "The name for more than one. Blank: the plural of the name above, or " \
      "#{Inventory::Config::DEFAULT_MACHINE_NAME_PLURAL} when that's blank too")

  # Pickers and the Setup page come with the settings inputs seam; without
  # it the settings stay text boxes and Setup shows plain fields.
  if picked
    snake = ->(text) { text.downcase.tr(" ", "_") }
    Settings.input(:inventory_users, :teams)
    Settings.input(:inventory_managers, :badge_grants, badges: -> { Badge.added_by_admin },
      blank_team_label: "Up to: every team")
    Settings.input(:inventory_member_kinds, :checkboxes, normalize: snake,
      choices: Inventory::Config::KINDS.map { |kind| [ kind.capitalize, kind ] })
    Settings.input(:inventory_member_unit_actions, :checkboxes, normalize: snake,
      choices: Inventory::Config::UNIT_ACTIONS.map { |action| [ action.humanize, action ] })
    Settings.input(:inventory_reorder_notice, :select,
      choices: Inventory::Config::REORDER_NOTICE_CHOICES)
    Settings.input(:inventory_machines, :select, choices: [ [ "On", "on" ], [ "Off", "off" ] ])
    Settings.input(:inventory_default_unit, :text,
      suggestions: -> { Item.distinct.order(:unit).pluck(:unit).compact_blank })
  end
  if Settings.respond_to?(:page)
    Settings.page("Inventory", :inventory_setup_path, label: "Inventory setup",
      if: -> { GatherPack::Features.enabled?(:inventory) })
  end

  GatherPack::HookCatalog.register_targets(*Inventory::HOOK_TARGETS)
  GatherPack::HookCatalog.register_events(*Inventory::HOOK_EVENTS)

  # The reorder list's own actions on ticked items: Print and Download CSV.
  # Both only read, so they may run from a GET.
  routes = Rails.application.routes.url_helpers
  ticked = ->(rows) { rows.to_h { |item, quantity| [ item.id, quantity ] } }
  Inventory.extensions.register_reorder_action(:print, label: "Print", method: :get,
    path: ->(rows) { routes.inventory_reorder_path(print: 1, items: ticked.call(rows)) })
  Inventory.extensions.register_reorder_action(:csv, label: "Download CSV", method: :get,
    path: ->(rows) { routes.inventory_reorder_path(format: :csv, items: ticked.call(rows)) })

  # The managers' summary goes in the combined daily email or the Weekly
  # Infodump when the summaries feature (feature/digests) is present and on;
  # otherwise InventoryDigestJob sends its own daily email.
  if defined?(GatherPack::Digests)
    GatherPack::Digests.register(:inventory, label: "Inventory",
      delivery: -> { Inventory::Config.reorder_notice == "weekly" ? :weekly : :daily },
      build: ->(person, since:) {
        next unless Inventory.enabled?

        team_ids = InventoryNotices.managers[person]
        digest = Inventory::Digest.new(since: since).for_teams(team_ids || [])
        next if team_ids.nil? || digest.empty?

        GatherPack::Digests::Section.new(heading: "Inventory: #{digest.summary}", body: InventoryNotices.new.digest_body(digest))
      })
  end
end
