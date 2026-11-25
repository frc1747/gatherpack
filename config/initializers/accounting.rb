# Accounting: account status from a group's books. Sources are gateways
# registered under :accounting (Gateway::QuickbooksGateway); their records
# are copied into accounting_records. Routes are in config/routes/accounting.rb
# and recurring jobs in config/recurring.d/accounting.yml; both do nothing
# while the feature is off.
Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :accounting,
      label: "Accounting",
      description: "Account status, reminders and billing from your books or ledgers",
      default_enabled: false,
      nav_section: "Finance"
    )
  )

  # Record hooks fire only when the source's revision of a record changed.
  GatherPack::HookCatalog.register_targets("accounting_records")
  GatherPack::HookCatalog.register_events("accounting - sync failed")
end
