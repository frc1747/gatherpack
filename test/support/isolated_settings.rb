# Keeps the test suite away from storage/settings.pstore. Required before the
# environment loads, so the settings registered at boot go to a throwaway
# store; each test then gets its own empty one (so no value leaks between
# tests or parallel workers) and the defaults apply unless the test sets a value.
require "pstore"
require "tmpdir"
require "fileutils"
require "active_support"

module IsolatedSettings
  REAL_PATH = "storage/settings.pstore".freeze

  # Sends any store opened on the real settings path to a temporary file.
  module PStorePath
    def new(path, *args, **options)
      path = IsolatedSettings.boot_path if path.to_s == REAL_PATH
      super(path, *args, **options)
    end
  end

  def self.temporary_path
    Dir::Tmpname.create([ "gp-test-settings-#{Process.pid}-", ".pstore" ]) { }
  end

  # The store for anything opened on the real path before the first test; removed at exit.
  def self.boot_path
    @boot_path ||= temporary_path.tap { |path| at_exit { FileUtils.rm_f(path) } }
  end

  def self.included(base)
    base.setup do
      @isolated_settings_original = Settings.instance.store
      @isolated_settings_path = IsolatedSettings.temporary_path
      Settings.instance.store = PStore.new(@isolated_settings_path, true)
    end
    base.teardown do
      Settings.instance.store = @isolated_settings_original
      FileUtils.rm_f(@isolated_settings_path)
    end
  end
end

PStore.singleton_class.prepend(IsolatedSettings::PStorePath)
ActiveSupport.on_load(:active_support_test_case) { include IsolatedSettings }

# A Rake prerequisite of `bin/rails test` can build the singleton on the real path
# before this file loads; point it at a temporary store too.
if Object.const_defined?(:Settings) && (settings = Settings.instance_variable_get(:@singleton__instance__))
  settings.store = PStore.new(IsolatedSettings.boot_path, true)
end
