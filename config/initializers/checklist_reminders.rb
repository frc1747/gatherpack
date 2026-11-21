# Checklist reminders: Send Reminder on a checklist, scheduled reminders on
# its Edit page, and what reminders may say about each item
# (Checklists::EmailLevel). Off by default (feature_checklist_reminders).
# Patches Checklist, ChecklistItem and the item kinds from here, so their
# files don't change.
Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :checklist_reminders,
      label: "Checklist reminders",
      description: "Organizers remind people what's left on a checklist, by hand or on a schedule, with control over what an email may say",
      default_enabled: false
    )
  )

  Checklists::EmailLevel::LEVELS.each do |level|
    Settings.register(Checklists::EmailLevel::LABEL_SETTINGS[level], :string, "Reminder Level Label: #{Checklists::EmailLevel::DEFAULT_LABELS[level]}",
      Checklists::EmailLevel::DEFAULT_LABELS[level], "Checklists", "The words for this choice of what checklist reminders may say")
  end

  GatherPack::HookCatalog.register_events(ChecklistReminder::CREATED_EVENT)

  Checklist.include(Checklists::ReminderSettings)
  ChecklistItem.include(Checklists::ItemEmailLevel)

  Checklists::ItemKind.singleton_class.include(Checklists::EmailCeiling)
  Checklists::Kinds::PersonField.singleton_class.prepend(Checklists::EmailCeiling::PersonField)
  Checklists::Kinds::AnyOf.singleton_class.prepend(Checklists::EmailCeiling::AnyOf)
  Checklists::Kinds::Checklist.singleton_class.prepend(Checklists::EmailCeiling::ChecklistItem)

  Checklists::ReminderDigest.register if defined?(GatherPack::Digests) && GatherPack::Digests.respond_to?(:register)
end
