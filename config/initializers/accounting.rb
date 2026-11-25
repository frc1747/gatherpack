# Accounting: account status from a group's books. Sources are gateways
# registered under :accounting (Gateway::QuickbooksGateway,
# Gateway::LedgerSource, Gateway::FileSource); their records are copied
# into accounting_records, and accounting_customer_links say which people
# each customer is for. Rules (accounting_rules) answer a question about
# each person from those records; the answers are shown on Account Status
# and each person's Account tab. Routes are in config/routes/accounting.rb
# and recurring jobs in config/recurring.d/accounting.yml; both do nothing
# while the feature is off.
Rails.application.config.to_prepare do
  # The sidebar item shows only to people who see some rule's results where
  # nav items can say who they're for (feature/nav-item-visible); without
  # that it shows to everyone while the feature is on, and the list says
  # when there's nothing to see.
  nav_visibility = GatherPack::Feature::NavItem.members.include?(:visible) ? { visible: ->(user) { Accounting::Access.sees_any_rule?(user) } } : {}

  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :accounting,
      label: "Accounting",
      description: "Account status, reminders and billing from your books or ledgers",
      default_enabled: false,
      nav_section: "Finance",
      nav_items: [ GatherPack::Feature::NavItem.new(label: "Account Status", path: :accounting_rules_path, icon: "file-invoice-dollar",
                                                    **nav_visibility) ],
      profile_tabs: [ GatherPack::Feature::ProfileTab.new(label: "Account", path: ->(person) { person_accounting_path(person) },
                                                          visible: ->(user, person) { Accounting::Access.sees_any_result?(user, person) }) ]
    )
  )

  # Badge grants let treasurers who aren't leaders see rules' results; a
  # badge with grants must stay one only admins assign.
  Badge.include(BadgeAccessGrants)
  Badge.has_many :accounting_rule_badge_grants, dependent: :destroy
  Badge.register_access_grants(:accounting_rule_badge_grants)
  Team.has_many :accounting_rules, inverse_of: :team, dependent: :nullify
  Person.include(Accounting::PersonResults)

  # Record hooks fire only when the source's revision of a record changed.
  GatherPack::HookCatalog.register_targets("accounting_records", "accounting_customer_links", "accounting_rules")
  GatherPack::HookCatalog.register_events("accounting - sync failed")
  # model is a new customer record the sync couldn't link to anyone.
  GatherPack::HookCatalog.register_events("accounting - customer unlinked")
  # model is an AccountingRuleChange, after the result is saved.
  GatherPack::HookCatalog.register_events(Accounting::Evaluation::EVENT)

  # Gateway types can choose their settings' inputs (the ledger source's
  # teams and tags are tick boxes and choices).
  Gateway.include(GatewayFieldInput) unless Gateway < GatewayFieldInput

  # Ledger sources read the ledgers again whenever one of these changes.
  [ Ledger, LedgerEntry, LedgerTagging, LedgerOwnership ].each do |model|
    model.include(Accounting::LedgerChanges) unless model < Accounting::LedgerChanges
  end

  # Ledger owner links leave out a guardian of another owner, so they're
  # brought up to date when guardianship changes.
  [ Relationship, RelationshipType ].each do |model|
    model.include(Accounting::GuardianshipChanges) unless model < Accounting::GuardianshipChanges
  end
end
