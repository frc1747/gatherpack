# Reads the kiosk settings straight from the settings file on every call.
# Settings caches values per process, so a change saved through one Puma
# worker wouldn't reach the others until a restart.
class TimeKiosk::Config
  STORE_LOCK = Mutex.new

  class << self
    def allow_unassigned?
      read(:time_kiosk_allow_unassigned).to_s != "false"
    end

    def return_seconds
      [ read(:time_kiosk_return_seconds).to_i, 0 ].max
    end

    def users_team
      id = read(:time_kiosk_users_team).presence
      Team.find_by(id: id) if id
    end

    # Reads through the store that opened the transaction: another thread
    # may replace the memoized store in the meantime.
    def read(key)
      current = store
      current.transaction(true) { current[key] }
    end

    private

    # A thread-safe store of our own: Settings' store isn't, and a second thread
    # entering its transaction raises instead of waiting.
    def store
      STORE_LOCK.synchronize do
        @store = nil unless @store_pid == Process.pid
        @store_pid = Process.pid
        @store ||= PStore.new(store_path, true)
      end
    end

    # Tests get an empty file per process, so parallel test workers and a
    # developer's own kiosk settings can't leak into each other.
    def store_path
      return Settings.instance.store.path unless Rails.env.test?

      Rails.root.join("tmp", "time_kiosk_settings_#{Process.pid}.pstore").to_s
    end
  end
end
