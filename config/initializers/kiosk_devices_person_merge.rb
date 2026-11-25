# Kiosk devices' column for the person merge registry. Guarded, so this
# branch runs without feature/person-merge. to_prepare runs after every
# initializer, so the registry is loaded by then whatever the file order.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  GatherPack::PersonMerge.register :kiosk_devices, :created_by_id, owner: :user, label: "Kiosk devices paired"
end
