# Sets Settings values for the duration of a block. Writes go to a throwaway
# PStore so tests never touch storage/settings.pstore, and the previous
# values are restored afterwards.
module SettingsTestHelper
  def with_settings(values)
    settings = Settings.instance
    original_store = settings.store
    settings.store = PStore.new(Rails.root.join("tmp", "test-settings-#{Process.pid}.pstore").to_s)
    previous = values.keys.to_h { |key| [ key, Settings.get(key).instance_variable_get(:@value) ] }
    values.each { |key, value| Settings[key] = value }
    yield
  ensure
    previous&.each { |key, value| Settings[key] = value }
    settings.store = original_store
  end
end
