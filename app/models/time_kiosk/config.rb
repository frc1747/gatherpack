# Reads the kiosk settings straight from the settings file on every call.
# Settings caches values per process, so a change saved through one Puma
# worker wouldn't reach the others until a restart.
class TimeKiosk::Config
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

    def read(key)
      store.transaction(true) { store[key] }
    end

    private

    # A thread-safe store of our own: Settings' store isn't, and a second thread
    # entering its transaction raises instead of waiting.
    def store
      @store ||= PStore.new(Settings.instance.store.path, true)
    end
  end
end
