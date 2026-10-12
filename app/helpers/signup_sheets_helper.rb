module SignupSheetsHelper
  # "Sat Oct 24, 2026 10:00 AM", or "Sat Oct 24, 2026, time not set yet"
  # for an event entered as 00:00 to 23:59.
  def signup_event_when(event, format: "%a %b %-d, %Y %-l:%M %p")
    if SignupNotices.time_unset?(event.start_time, event.end_time)
      "#{event.start_time.strftime(format.sub(/,?\s*%-l:%M %p/, ""))}, time not set yet"
    else
      event.start_time.strftime(format)
    end
  end

  # A person's name as an on-behalf-of choice, followed by the hints other
  # features add (Signups.extensions), such as what they still owe.
  def signup_on_behalf_of_label(sheet, person)
    hint = Signups.extensions.on_behalf_of_hint(sheet, person)
    return person.identifier_name if hint.nil?

    safe_join([ person.identifier_name, " ", tag.span("(#{hint})", class: "small text-body-secondary signup-hint") ])
  end
end
