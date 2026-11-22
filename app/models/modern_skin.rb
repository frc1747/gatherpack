# The modern skin: a separate stylesheet, a folder of replacement templates and
# a person's Light/Dark/Auto choice. Registered in config/initializers/modern_skin.rb.
module ModernSkin
  COLOR_MODES = %w[light dark].freeze

  # Shared devices: their mode shouldn't change with the person or the hour.
  ALWAYS_LIGHT_LAYOUTS = %w[kiosk intake_kiosk].freeze

  # Runs on every request, signed-out ones included.
  def self.active?(controller)
    GatherPack::Features.enabled?(:modern_skin) || previewing?(controller)
  end

  def self.previewing?(controller)
    controller.session[:skin_preview] == true
  end

  # "light", "dark", or nil for Auto. Uses the real user, so impersonating
  # someone doesn't change an admin's mode.
  def self.color_mode_for(controller)
    return "light" if ALWAYS_LIGHT_LAYOUTS.include?(controller.class._layout.to_s)

    controller.true_user&.color_mode.presence_in(COLOR_MODES)
  end
end
