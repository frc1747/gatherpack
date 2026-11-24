# Menu pins point at a login, registered where people can be merged
# (GatherPack::PersonMerge); without it there's nothing to register. Pins are
# personal display state and unique per login, so the merged-away login's
# pins are deleted rather than moved.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  GatherPack::PersonMerge.register :menu_pins, :user_id, action: :delete, owner: :user, label: "Menu pins"
end
