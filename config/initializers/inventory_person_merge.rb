# Inventory's columns that point at a person, registered where people can be
# merged (GatherPack::PersonMerge); without it there's nothing to register.
# GatherPack::PersonMerge is required by its own initializer, and to_prepare
# runs after every initializer has loaded, so file order doesn't matter.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  merge = GatherPack::PersonMerge

  merge.register :stock_movements, :person_id, label: "Stock changes"
  merge.register :stock_movements, :recorded_by_id, label: "Stock changes recorded"
  merge.register :item_unit_events, :person_id, label: "Part history"
  merge.register :item_unit_events, :recorded_by_id, label: "Part history recorded"
end
