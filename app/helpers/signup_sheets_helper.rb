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

  # The taker as Cancel's question and its flash call them. first_name can be
  # blank.
  def signup_taker_name(signup)
    signup.person.first_name.presence || signup.person.identifier_name
  end

  # Which place Cancel is about: "Cashier, Game Day", with the event's date
  # when the sheet has more than one, since events can share a name.
  def signup_place_name(signup)
    event = signup.event
    parts = [ signup.signup_position.name, event.name ]
    parts << event.start_time.strftime("%a %b %-d") if signup.signup_sheet.events.many?
    parts.join(", ")
  end

  # Whether cancelling from the roster reaches the taker: SignupNotices#cancelled
  # emails them if they have an address and a gateway can send it.
  def signup_taker_told?(signup)
    signup.person.user&.email.present? && Gateway.any_registered?(:email_sending)
  end

  # What Cancel asks. told: the cancel emails the taker, which the roster's
  # can (signup_taker_told?) and a member's doesn't.
  def signup_cancel_confirmation(signup, viewer:, told: false)
    return "Cancel this sign-up?" if signup.person_id == viewer.id

    question = "Cancel #{signup_taker_name(signup)}'s place in #{signup_place_name(signup)}?"
    told ? "#{question} They'll be told." : question
  end

  # A person's name as an on-behalf-of choice, followed by the hints other
  # features add (Signups.extensions), such as what they still owe.
  def signup_on_behalf_of_label(sheet, person)
    hint = Signups.extensions.on_behalf_of_hint(sheet, person)
    return person.identifier_name if hint.nil?

    safe_join([ person.identifier_name, " ", tag.span("(#{hint})", class: "small text-body-secondary signup-hint") ])
  end
end
