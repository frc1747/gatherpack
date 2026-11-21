Rails.application.config.to_prepare do
  Event.include(Events::Duplicate)
  EventsController.include(EventsDuplicating)

  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :event_duplicate,
      label: "Duplicate events",
      description: "Events get a Duplicate action that starts a new event from an old one",
      default_enabled: false
    )
  )
end
