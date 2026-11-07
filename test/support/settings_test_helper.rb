# Sets Settings values for the duration of a block. Writes go to a throwaway
# PStore so tests never touch storage/settings.pstore, and the previous
# values are restored afterwards. Each block gets its own copy of the current
# store, so a nested block can't overwrite the outer one's values.
module SettingsTestHelper
  def with_settings(values)
    restore = SettingsTestHelper.apply(values)
    yield
  ensure
    restore&.call
  end

  # Swaps in a copy of the current store with values set, until the returned
  # proc is called.
  def self.apply(values)
    settings = Settings.instance
    original_store = settings.store
    path = Rails.root.join("tmp", "test-settings-#{Process.pid}-#{SecureRandom.hex(4)}.pstore").to_s
    current = original_store.transaction(true) { original_store.roots.to_h { |key| [ key, original_store[key] ] } }
    settings.store = PStore.new(path, true)
    settings.store.transaction { current.each { |key, value| settings.store[key] = value } }
    # Builds that cache each value in the process keep it in @value.
    previous = values.keys.to_h { |key| [ key, Settings.get(key).instance_variable_get(:@value) ] }
    values.each { |key, value| Settings[key] = value }
    lambda do
      previous.each { |key, value| Settings.get(key).instance_variable_set(:@value, value) }
      settings.store = original_store
      FileUtils.rm_f(path)
    end
  end
end
