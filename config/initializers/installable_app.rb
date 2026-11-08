require_relative "../../lib/gatherpack/service_worker"

# Installable app: a short name for the home screen, a service worker that caches
# only digested assets and the offline page, and an install entry in the sidebar.
# The flag turns it all off; a device that already has the worker removes it the
# next time it checks (see app/views/pwa/service-worker.js.erb).
Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :installable_app,
      label: "Installable app",
      description: "Let people add this site to their phone's home screen",
      default_enabled: false
    )
  )

  settings = Settings.instance
  settings.send(:add_setting, :pwa_short_name, :string, "Name on the home screen", "", "App",
    "Shown under the icon when someone adds this site to their home screen (12 characters or fewer). Leave blank to use the site name.")
  settings.send(:add_setting, :pwa_description, :string, "App description", "Get together with GatherPack", "App",
    "Shown when someone installs the app")

  GatherPack::SidebarSlots.register(:install_help, partial: "pwa/install_help", position: 900,
    visible: ->(_view) { GatherPack::Features.enabled?(:installable_app) })

  # The browser re-fetches the worker script on every navigation; make sure no
  # cache in between can hold on to an old one.
  Rails::PwaController.after_action(only: :service_worker) do
    response.headers["Cache-Control"] = "no-cache"
  end
end
