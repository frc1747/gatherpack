# Kiosk devices: computers an admin pairs once to run the time kiosk with no
# one signed in (see KioskDevice). Off by default; while off, the pairing
# links answer 404 and device cookies are ignored.
Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :kiosk_devices,
      label: "Kiosk Devices",
      description: "Pair a computer to run the time kiosk without anyone signed in",
      default_enabled: false,
      setup_section: "Time",
      nav_position: 21,
      setup_items: [
        GatherPack::Feature::SetupItem.new(label: "Kiosk Devices", path: :kiosk_devices_path, policy_check: ->(view) { view.admin? })
      ]
    )
  )
end
