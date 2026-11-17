module EventsHelper
  TBA_LABEL = "Time TBA"

  def format_event_time_date(event, format_type, include_location)
    parts = if event.timed?
      [
        event.start_time.to_fs(format_type),
        event.end_time == nil ? "" :
          " - " + event.end_time.to_fs(format_type)
      ]
    else
      [ event.start_time.to_date.to_fs(format_type), event.tba? ? " - #{TBA_LABEL}" : "" ]
    end
    if include_location && event.location.present?
      parts << " at " + event.location
    end

    parts.join
  end

  def event_time_summary(event)
    return nice_datetime(event.start_time) if event.timed?

    event.tba? ? "#{nice_date(event.start_time)} - #{TBA_LABEL}" : nice_date(event.start_time)
  end

  # The time-related attributes of a FullCalendar event. All-day entries carry a
  # plain date so the calendar's time zone can't move them to another day.
  def event_calendar_times(event)
    return { title: event.name, allDay: false, start: event.start_time, end: event.end_time } if event.timed?

    { title: event.tba? ? "#{event.name} (TBA)" : event.name, allDay: true, start: event.start_time.to_date, end: nil }
  end

  def event_as_badge(event, **opts)
    time = if event.timed?
      event.start_time
    else
      event.tba? ? "#{event.start_time.to_date}, #{TBA_LABEL}" : event.start_time.to_date
    end
    content = i("calendar") + " #{event.identifier_name} (#{time})"
    content +=" - #{event.team.name}" if event.team
    link_to event, class: "undecorated" do
      tag.span content, class: "badge", style: "background-color: #{event.team&.color || "#0dcaf0"};"
    end
  end
end
