# Order requests: the feature switch, settings, menu section and hook
# events. Uses config.to_prepare (like features.rb) so the registrations are
# replayed after each development reload.
Rails.application.config.to_prepare do
  # Setup is a button on the main Setup page, not a menu item: one Setup in the menu.
  orders_setup_item = GatherPack::Feature::SetupItem.new(label: "Orders", path: :orders_settings_path,
    policy_check: ->(view) { OrderSettingsPolicy.new(view.current_user, :order_settings).show? })
  # Approval steps are a managed list with a screen of their own, since each
  # step has approver rows the shared list form has no place for.
  approval_steps_item = GatherPack::Feature::SetupItem.new(label: "Approval Steps", path: :orders_approval_steps_path,
    policy_check: ->(view) { ManagedListPolicy.new(view.current_user, ApprovalStep).index? })

  # To approve is for approvers; to buy and Reports are refused to most members, so they're hidden where
  # menu items take a visible check (the same guard as the Setup page).
  to_buy_visible = {}
  reports_visible = {}
  to_approve_visible = {}
  if Orders::SettingsEditor.in_menu?
    to_approve_visible[:visible] = ->(user) { Orders::Access.for(user&.person).approver? }
    to_buy_visible[:visible] = ->(user) { PurchasePolicy.new(user, Purchase).create? }
    reports_visible[:visible] = ->(user) { OrderReportPolicy.new(user, :order_report).index? }
  end

  GatherPack::Features.register_section("Purchasing", position: 35)
  # Setup's heading for orders (and inventory), where Purchasing sat: after Finance.
  GatherPack::Features.register_section(Orders::SETUP_SECTION, position: 35)

  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :orders,
      label: "Orders",
      description: "Members ask for things to be bought; approvers approve, buyers buy, and the people who asked receive",
      default_enabled: false,
      nav_section: "Purchasing",
      nav_position: 10,
      nav_items: [
        GatherPack::Feature::NavItem.new(label: "Orders", path: :orders_requests_path, icon: "cart-shopping"),
        GatherPack::Feature::NavItem.new(label: "To approve", path: :orders_approvals_path, icon: "stamp", **to_approve_visible),
        GatherPack::Feature::NavItem.new(label: "To buy", path: :to_buy_orders_purchases_path, icon: "credit-card", **to_buy_visible),
        GatherPack::Feature::NavItem.new(label: "To receive", path: :orders_deliveries_path, icon: "box-open"),
        GatherPack::Feature::NavItem.new(label: "Vendors", path: :orders_vendors_path, icon: "store"),
        GatherPack::Feature::NavItem.new(label: "Funding sources", path: :orders_funding_sources_path, icon: "hand-holding-dollar"),
        GatherPack::Feature::NavItem.new(label: "Reports", path: :orders_reports_path, icon: "chart-column", **reports_visible)
      ],
      setup_section: Orders::SETUP_SECTION,
      setup_items: [ orders_setup_item, approval_steps_item ]
    )
  )

  Settings.register(:orders_requesters, :text, "Who Can Request", "", "Orders",
    "Teams whose members (and members of the teams below) may ask for things to be bought, or rows as for Buyers. Blank: everyone signed in")
  Settings.register(:orders_viewers, :text, "Who Sees Every Request", "", "Orders",
    "Teams whose members (and members of the teams below) see every request that isn't a draft, and may comment " \
    "when team members can. Seeing doesn't let them approve, buy or receive. Blank: nobody extra")
  Settings.register(:orders_buyers, :text, "Buyers", "", "Orders",
    "Who buys, one row per line: Badge name, Managers of Team name (that team's own managers), or Managers of each team; add \"> Team name\" for that team and " \
    "the teams below it, else every team. Admins always can. Blank: admins only")
  Settings.register(:orders_price_tolerance, :string, "Price Tolerance", Orders::Config::DEFAULT_TOLERANCE, "Orders",
    "How far a buyer's changes may raise an approved total without approving again: a percentage and an amount, " \
    "whichever is larger (for example \"10%, 25\")")
  Settings.register(:orders_team_can_see, :boolean, "Team Members See Requests", "true", "Orders",
    "Members of a request's team see it, comment on it and receive it")
  Settings.register(:orders_require_other_vendor_reason, :boolean, "Other Store Needs a Reason", "false", "Orders",
    "An item from a store that isn't listed needs a reason")
  Settings.register(:orders_funding_managers, :text, "Funding Managers", "", "Orders",
    "Who manages funding sources, one row per line as for Buyers. Admins always can. Blank: admins only")
  Settings.register(:orders_require_funding_source, :boolean, "Require a Funding Source", "false", "Orders",
    "A request needs a funding source before its final approval")
  Settings.register(:orders_requesters_pick_funding, :boolean, "Requesters Pick Funding", "false", "Orders",
    "Requesters see and may choose a funding source. Off: approvers set it")
  Settings.register(:orders_close_after_days, :integer, "Close Received Requests After (days)", "14", "Orders",
    "Received requests close after this many days")
  Settings.register(:orders_notices, :string, "Order Notices", Orders::Config::DEFAULT_NOTICES, "Orders",
    "How people hear about requests: approvers about requests waiting for them, requesters and watchers about their " \
    "requests, buyers about what's ready to buy. Each person can change this for themselves.")

  # Orders setup (Orders::SettingsEditor) draws every orders setting, with
  # the settings pickers where they exist, and the settings page links there
  # while orders is on. Buyers and funding managers have no picker there:
  # their grant rows (Orders::GrantRows) are drawn on Orders setup only, so
  # the settings page shows them as text in the line format of their hints.
  if Settings.respond_to?(:input)
    Settings.input(:orders_requesters, :teams)
    Settings.input(:orders_viewers, :teams)
    Settings.input(:orders_notices, :select, choices: Orders::Config::NOTICE_CHOICES)
    Settings.input(:orders_price_tolerance, :partial, partial: "orders/settings/price_tolerance",
      to_text: ->(posted, current) { Orders::PriceToleranceField.text_from(posted, current) }, default_label: Orders::Config::DEFAULT_TOLERANCE)
  end
  Settings.page("Orders", :orders_settings_path, label: "Orders setup", if: -> { GatherPack::Features.enabled?(:orders) }) if Settings.respond_to?(:page)

  # The things an orders group names for itself (GatherPack::ManagedLists).
  if defined?(GatherPack::ManagedLists)
    ManagedListsController.include(Orders::ManagedListRefusals) unless ManagedListsController < Orders::ManagedListRefusals
    GatherPack::ManagedLists.register(:payment_methods, model: "PaymentMethod", label: "Payment Method",
      plural_label: "Payment Methods", setup_section: Orders::SETUP_SECTION, feature: :orders,
      description: "How a purchase can be paid. One that needs paying back marks the buyer to be repaid.",
      fields: [ { name: :reimburse, label: "Needs paying back", hint: "The buyer paid with their own money." } ])
    GatherPack::ManagedLists.register(:delivery_problem_kinds, model: "DeliveryProblemKind", label: "Delivery Problem",
      plural_label: "Delivery Problems", setup_section: Orders::SETUP_SECTION, feature: :orders,
      description: "What can be wrong with something that arrives. Picking one makes the item a problem for its buyer to settle.")
    # No setup_section: Setup links to the approval steps' own screen.
    GatherPack::ManagedLists.register(:approval_steps, model: "ApprovalStep", label: "Approval Step",
      plural_label: "Approval Steps", feature: :orders,
      description: "The approvals a request needs, in order.")
  end

  # The Orders section of the daily email and the Weekly Infodump. Where
  # this seam isn't merged, or Summaries is off, Orders::DigestJob sends it.
  if defined?(GatherPack::Digests)
    GatherPack::Digests.register(:orders, label: "Orders", delivery: -> { Orders::Config.notices },
      build: ->(person, since:) { Orders::Digest.section(person, since: since) })
  end

  GatherPack::HookCatalog.register_targets(*Orders::HOOK_TARGETS)
  GatherPack::HookCatalog.register_events(*Orders::HOOK_EVENTS)
end
