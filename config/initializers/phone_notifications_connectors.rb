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

  # It's a person's own setting, so with My GatherPack on it goes beside Sign Out.
  visible = -> { GatherPack::PushChannel.available? && current_user == true_user }
  MyGatherpack.register_account_link(:notifications, label: "Notifications", path: :notifications_path, visible: visible)
  GatherPack::SidebarSlots.register(:phone_notifications, partial: "my_gatherpack/notifications_sidebar_entry", position: 800,
    visible: ->(_view) { GatherPack::PushChannel.available? && current_user == true_user })
end
