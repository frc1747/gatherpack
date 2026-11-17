# Template overrides: features register a folder of replacement templates with
# GatherPack::ViewOverrides.register (see lib/gatherpack/view_overrides.rb).
# lib/gatherpack is not autoloaded, so it is required here. to_prepare runs
# again on each development reload; including the concern is a no-op the second
# time for the same class, and a reloaded ApplicationController is a new class.
require_relative "../../lib/gatherpack/view_overrides"

Rails.application.config.to_prepare do
  ApplicationController.include(GatherPack::ViewOverrides::Controller)
end
