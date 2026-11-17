require "tmpdir"

# Sets values through Settings against a throwaway copy of the store, so
# parallel workers never write the shared settings file.
module ModernSkinTestSettings
  def with_setting(key, value)
    restore = override_setting(key, value)
    yield
  ensure
    restore&.call
  end

  # Returns a proc that puts the value and the store back.
  def override_setting(key, value)
    settings = Settings.instance
    original_store = settings.store
    original_value = Settings[key].to_s
    dir = Dir.mktmpdir("modern-skin-settings")
    copy = PStore.new(File.join(dir, "settings.pstore"), true)
    stored = original_store.transaction(true) { original_store.roots.to_h { |name| [ name, original_store[name] ] } }
    copy.transaction { stored.each { |name, saved| copy[name] = saved } }
    settings.store = copy
    Settings[key] = value

    lambda do
      Settings[key] = original_value
      settings.store = original_store
      FileUtils.remove_entry(dir)
    end
  end
end
