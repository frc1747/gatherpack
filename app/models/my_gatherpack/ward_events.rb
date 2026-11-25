module MyGatherpack
  # A ward's upcoming team events, for a guardian's family page: when and
  # where, and nothing about who came. An event page lists other families'
  # children, so EventPolicy::Scope stays as it is and a row carries its
  # event only when the viewer's own scope already includes it.
  class WardEvents
    LIMIT = 5

    Row = Struct.new(:title, :start_time, :end_time, :location, :event, keyword_init: true)

    # +viewer_events+ is the viewer's policy_scope(Event).
    def initialize(ward, viewer_events:, limit: LIMIT)
      @ward = ward
      @viewer_events = viewer_events
      @limit = limit
    end

    def rows
      events = Event.where(team_id: @ward.all_teams.select(:id))
        .where("COALESCE(end_time, start_time) >= ?", Time.current)
        .order(:start_time, :name)
        .limit(@limit)
        .to_a
      reachable = @viewer_events.where(id: events.map(&:id)).pluck(:id).to_set

      events.map do |event|
        Row.new(title: event.name, start_time: event.start_time, end_time: event.end_time, location: event.location,
          event: (event if reachable.include?(event.id)))
      end
    end
  end
end
