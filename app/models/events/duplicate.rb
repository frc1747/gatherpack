module Events
  # Starts a new event from an existing one. Nothing is saved: the attributes
  # prefill New Event so the date is chosen before saving.
  module Duplicate
    def duplicate_attributes
      {
        event_type_id: event_type_id,
        team_id: team_id,
        name: "#{name} (copy)",
        location: location,
        description: description,
        start_time: start_time,
        end_time: end_time,
        time_kind: time_kind,
        checkin_limit: checkin_limit,
        locked: locked,
        time_clock_period_id: time_clock_period_id
      }
    end
  end
end
