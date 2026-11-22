# Checklist reminders' column that points at a person, registered where people
# can be merged (GatherPack::PersonMerge); without it there's nothing to register.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  GatherPack::PersonMerge.register :checklist_reminders, :sent_by_id, label: "Checklist reminders sent"
end
