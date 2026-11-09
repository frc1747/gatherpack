# Phone notifications for forms, sign-up sheets and commitments, on top of the
# emails those already send. Each topic is offered only while its feature is on.
Rails.application.config.to_prepare do
  FormReminderSender.prepend(FormReminderPushConnector)
  SignupNotices.prepend(SignupNoticesPushConnector)
  CommitmentsController.prepend(CommitmentsPushConnector)

  GatherPack::PushTopics.register(:forms, label: "Forms", hint: "When a leader sends a reminder", default_on: false,
    available: -> { GatherPack::Features.enabled?(:forms) })
  GatherPack::PushTopics.register(:shifts, label: "My shifts", hint: "Reminders, and when a shift's time changes or it is cancelled or moved", default_on: false,
    available: -> { GatherPack::Features.enabled?(:signups) })
  GatherPack::PushTopics.register(:commitments, label: "What I still owe", hint: "When an organizer sends a message", default_on: false,
    available: -> { GatherPack::Features.enabled?(:commitments) })
end
