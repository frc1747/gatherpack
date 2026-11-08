require "tmpdir"

# Runs each test against a throwaway settings store and puts the values and
# the page lists back afterwards, so nothing here can reach later tests on
# this worker.
module SmoothPagesTestSettings
  extend ActiveSupport::Concern

  included do
    setup do
      @settings_dir = Dir.mktmpdir("smooth-pages-settings")
      @original_store = Settings.instance.store
      @original_values = {}
      Settings.instance.store = PStore.new(File.join(@settings_dir, "settings.pstore"))
      @original_pages = %i[@refresh_pages @no_preview_pages].to_h do |name|
        [ name, GatherPack::SmoothPages.instance_variable_get(name).dup ]
      end
      @original_fingerprints = GatherPack::SidebarSlots.instance_variable_get(:@fingerprints).dup
      @original_plugins = GatherPack::Features.instance_variable_get(:@plugins).dup
    end

    teardown do
      @original_pages.each { |name, pages| GatherPack::SmoothPages.instance_variable_set(name, pages) }
      GatherPack::SidebarSlots.instance_variable_set(:@fingerprints, @original_fingerprints)
      GatherPack::Features.instance_variable_set(:@plugins, @original_plugins)
      @original_values.each { |key, value| Settings[key] = value }
      Settings.instance.store = @original_store
      FileUtils.remove_entry(@settings_dir)
    end
  end

  def set_flag(key, enabled)
    @original_values[key] = Settings.get(key).instance_variable_get(:@value) unless @original_values.key?(key)
    Settings[key] = enabled.to_s
  end
end
