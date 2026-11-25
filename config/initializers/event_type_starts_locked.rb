Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: EventTypes::StartsLocked::FEATURE,
      label: "Event types that start locked",
      description: "An event type can make its new events start locked, " \
        "so only admins and the team's managers can check people in",
      default_enabled: false
    )
  )

  Event.include(EventTypes::StartsLocked)
  EventTypesController.prepend(EventTypes::StartsLockedParams)
end
