Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :forms_auto_reminders,
      label: "Automatic form reminders",
      description: "Email people who haven't answered a form a few days before its deadline",
      default_enabled: false
    )
  )

  Form.include(FormAutoReminders)
end
