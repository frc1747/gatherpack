# The flag for the monthly reminder of what people still owe. It has no pages
# of its own: it shows the checkbox on a commitment's edit page and lets
# CommitmentMonthlyReminderJob send, and only while Commitments is on too.
Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :commitment_monthly_reminders,
      label: "Monthly commitment reminders",
      description: "Email people who still owe on a commitment once a month, when its organizer asks for it",
      default_enabled: false
    )
  )
end
