# Domain events that features fire by hand (Hook.where(event: ...)), which
# CanBeHooked's create/update/destroy callbacks don't cover. Model events come
# from the models themselves; see Hook.catalog.
Rails.application.config.to_prepare do
  GatherPack::HookCatalog.register_events(
    "person_fields - value changed",
    "form_submissions - submitted",
    "form_submissions - activated",
    "form_responses - completed",
    "form_responses - incomplete"
  )
end
