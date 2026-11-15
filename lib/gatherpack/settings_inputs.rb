# How the settings page draws a setting, kept apart from Settings.register so
# a setting can get a picker without changing how it is stored. The picker
# saves the same text a typed value would, so whatever reads the setting
# doesn't change. Draw and parse logic is in SettingInput (app/models).
#
# A feature calls these in its initializer's to_prepare block, guarded so the
# feature still works (with a text box) where this seam isn't merged:
#
#   Settings.input(:my_teams, :teams) if Settings.respond_to?(:input)
#   Settings.page("My Feature", :my_feature_setup_path) if Settings.respond_to?(:page)
class Settings
  Input = Data.define(:setting_key, :kind, :options)
  Page = Data.define(:group, :path, :label)

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
    # name (Symbol), a path, or a callable returning one.
    def page(group, path, label: nil)
      instance.pages[group] = Page.new(group, path, label)
    end

    def page_for(group)
      instance.pages[group]
    end
  end

  def inputs
    @inputs ||= {}
  end

  def pages
    @pages ||= {}
  end
end
