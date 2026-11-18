# How the settings page draws a setting, kept apart from Settings.register so
# a setting can get a picker without changing how it is stored. The picker
# saves the same text a typed value would, so whatever reads the setting
# doesn't change. Draw and parse logic is in SettingInput (app/models).
#
# A feature calls these in its initializer's to_prepare block, guarded so the
# feature still works (with a text box) where this seam isn't merged:
#
#   Settings.input(:my_teams, :teams) if Settings.respond_to?(:input)
#   Settings.input(:my_grants, :badge_grants, blank_team_label: "Up to: every team")
#     (the blank team choice says what a grant with no team means for this feature)
#   Settings.page("My Feature", :my_feature_setup_path,
#     if: -> { GatherPack::Features.enabled?(:my_feature) }) if Settings.respond_to?(:page)
#
# Pass if: when the page isn't always there (a feature that's off redirects
# away from it): while it's false the group is drawn on the settings page as
# usual, so its settings can still be set.
class Settings
  Input = Data.define(:setting_key, :kind, :options)
  Page = Data.define(:group, :path, :label, :condition) do
    def shown?
      condition.nil? || condition.call
    end
  end

  class << self
    # Draws setting_key with an input of the given kind instead of a text box.
    # Kinds and their options are listed in SettingInput::KINDS.
    def input(setting_key, kind, **options)
      SettingInput.class_for(kind) # Fails early on an unknown kind.
      instance.inputs[setting_key.to_sym] = Input.new(setting_key.to_sym, kind.to_sym, options)
    end

    def input_for(setting_key)
      instance.inputs[setting_key.to_sym]
    end

    # Shows a group's settings on the feature's own page: the settings page
    # lists the group as one line with a link there. path is a route helper
    # name (Symbol), a path, or a callable returning one. if: (a callable)
    # says whether the page is there right now.
    def page(group, path, label: nil, if: nil)
      instance.pages[group] = Page.new(group, path, label, binding.local_variable_get(:if))
    end

    # The group's page, or nil when it has none or its if: is false.
    def page_for(group)
      page = instance.pages[group]
      page if page&.shown?
    end
  end

  def inputs
    @inputs ||= {}
  end

  def pages
    @pages ||= {}
  end
end
