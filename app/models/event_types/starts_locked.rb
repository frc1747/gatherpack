# A new event whose type is marked "New events start locked" is created
# locked, so only admins and the team's managers can check people in.
# A manager can still unlock one event afterwards; changing an event's type
# later leaves its lock alone.
module EventTypes::StartsLocked
  extend ActiveSupport::Concern

  FEATURE = :event_type_starts_locked

  def self.enabled?
    GatherPack::Features.enabled?(FEATURE)
  end

  included do
    before_create :lock_if_event_type_starts_locked
  end

  private

  def lock_if_event_type_starts_locked
    self.locked = true if EventTypes::StartsLocked.enabled? && event_type&.starts_locked?
  end
end
