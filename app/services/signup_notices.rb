# Emails about sign-ups, sent like the other GatherPack notices: one
# SendEmailJob per recipient through the email gateway, so no one sees
# anyone else's address, and nothing is sent (but nothing fails) when no
# gateway is set up. A sign-up's notices go to the person taking the place,
# whoever signed them up and whoever it's on behalf of, if they have an
# email address. Nothing is sent while Sign-up Sheets are turned off.
class SignupNotices
  include ERB::Util

  # Events entered with no known time yet run 00:00 to 23:59 (spec §3.5).
  def self.time_unset?(start_time, end_time)
    return false if start_time.nil? || end_time.nil?

    start = local(start_time)
    finish = local(end_time)
    start.to_date == finish.to_date && start.strftime("%H:%M") == "00:00" && finish.strftime("%H:%M") == "23:59"
  end

  # "Sat Oct 24, 2026, 10:00 AM to 2:00 PM", or just the date when the
  # time isn't set yet.
  def self.when_text(event, start_time: event.start_time, end_time: event.end_time)
    start = local(start_time)
    date = start.strftime("%a %b %-d, %Y")
    return "#{date}, time not set yet" if time_unset?(start_time, end_time)

    text = "#{date}, #{start.strftime("%-l:%M %p")}"
    return text if end_time.nil?

    finish = local(end_time)
    text + " to " + (finish.to_date == start.to_date ? finish.strftime("%-l:%M %p") : finish.strftime("%a %b %-d, %-l:%M %p"))
  end

  def self.local(time)
    time.in_time_zone(Settings[:time_zone].presence || "UTC")
  end

  # To the person, the signer and whoever it's on behalf of, when a sign-up
  # is made.
  def confirmation(signup)
    deliver(recipients(signup), "Signed up: #{signup.signup_position.name}, #{signup.event.name}") do
      "<p>#{h(taker_phrase(signup))} signed up for <strong>#{h(signup.signup_position.name)}</strong> " \
        "on #{link_to_sheet(signup.signup_sheet)}.</p>#{signup_summary(signup)}"
    end
  end

  # A set number of days before the event (the sheet's reminder_days).
  def reminder(signup)
    deliver(recipients(signup), "Reminder: #{signup.signup_position.name}, #{signup.event.name}") do
      "<p>A reminder: #{h(taker_phrase(signup))} signed up for " \
        "<strong>#{h(signup.signup_position.name)}</strong> on #{link_to_sheet(signup.signup_sheet)}.</p>#{signup_summary(signup)}"
    end
  end

  # When an event's date or time changes, to everyone with an active
  # sign-up at it, on any sheet. Each person's email names only the sheets
  # their own sign-ups are on.
  def event_changed(event, start_time_was:, end_time_was:)
    signups = Signup.active.joins(:signup_slot).where(signup_slots: { event_id: event.id })
      .includes(:person, :signed_up_by, :on_behalf_of, signup_slot: { signup_position: :signup_sheet })
    sheets_by_person = Hash.new { |hash, person| hash[person] = [] }
    signups.each { |signup| recipients(signup).compact.each { |person| sheets_by_person[person] |= [ signup.signup_sheet ] } }
    was = self.class.when_text(event, start_time: start_time_was, end_time: end_time_was)
    now = self.class.when_text(event)

    deliver(sheets_by_person.keys, "Time changed: #{event.name}") do |person|
      "<p>The time of <strong>#{h(event.name)}</strong> has changed.</p>" \
        "<p>It was: #{h(was)}<br>It's now: <strong>#{h(now)}</strong>#{h(", #{event.location}") if event.location.present?}</p>" \
        "<p>You're signed up for it on #{sheets_by_person[person].map { |sheet| link_to_sheet(sheet) }.to_sentence}. " \
        "If you can't make the new time, please cancel or tell the organizers.</p>"
    end
  end

  # When an organizer cancels a sign-up from the roster.
  def cancelled(signup, by:)
    deliver(recipients(signup), "Sign-up cancelled: #{signup.signup_position.name}, #{signup.event.name}") do
      "<p>#{h(by&.display_name || "An organizer")} cancelled #{h(possessive(signup))} sign-up for " \
        "<strong>#{h(signup.signup_position.name)}</strong> on #{link_to_sheet(signup.signup_sheet)}.</p>#{signup_summary(signup)}"
    end
  end

  # When an organizer moves a sign-up to another slot.
  def moved(signup, from:, by:)
    deliver(recipients(signup), "Sign-up moved: #{signup.signup_position.name}, #{signup.event.name}") do
      "<p>#{h(by&.display_name || "An organizer")} moved #{h(possessive(signup))} sign-up on #{link_to_sheet(signup.signup_sheet)}.</p>" \
        "<p>It was: #{h(from.signup_position.name)}, #{h(from.event.name)}, #{h(self.class.when_text(from.event))}</p>" \
        "#{signup_summary(signup)}"
    end
  end

  # An organizer's message to everyone signed up for one date on a sheet
  # (active or fulfilled). Returns how many people it went to.
  def message(sheet, event, subject:, body:, from:)
    signups = sheet.signups.counted.joins(:signup_slot).where(signup_slots: { event_id: event.id })
      .includes(:person, :signed_up_by, :on_behalf_of)
    people = signups.flat_map { |signup| recipients(signup) }
    deliver(people, subject) do
      "<p>From #{h(from&.display_name || "the organizers")}, about #{h(event.name)} " \
        "(#{h(self.class.when_text(event))}) on #{link_to_sheet(sheet)}:</p>" \
        "#{simple_format(body)}" \
        "#{"<p>Contact: #{h(sheet.contact)}</p>" if sheet.contact.present?}"
    end
  end

  private

  # Sends one email per person with an address and returns how many. The
  # block gives the body, and is given the person.
  def deliver(people, subject)
    return 0 unless GatherPack::Features.enabled?(:signups)

    people = people.compact.uniq.select { |person| person.user&.email.present? }
    return 0 if people.empty?

    gateway = Gateway[:email_sending]
    people.each do |person|
      SendEmailJob.perform_later(gateway, person.user.email, "#{Settings[:title]} - #{subject}", "<p>Hi #{h(person.first_name)},</p>#{yield(person)}")
    end
    people.size
  end

  def recipients(signup)
    [ signup.person, signup.signed_up_by, signup.on_behalf_of ]
  end

  def taker_phrase(signup)
    "#{signup.person.display_name} is"
  end

  def possessive(signup)
    "#{signup.person.display_name}'s"
  end

  def signup_summary(signup)
    event = signup.event
    position = signup.signup_position
    lines = [ "<strong>#{h(event.name)}</strong>", h(self.class.when_text(event)) ]
    lines << h(event.location) if event.location.present?
    lines << "Bringing: #{h(signup.quantity)} #{h(signup.quantity == 1 ? position.unit_label.singularize : position.unit_label)}" if position.items?
    lines << "#{h(position.question)} #{h(signup.answer)}" if position.question.present? && signup.answer.present?
    lines << "On behalf of #{h(signup.on_behalf_of.display_name)}" if signup.on_behalf_of && signup.on_behalf_of_id != signup.person_id
    "<p>#{lines.join("<br>")}</p>"
  end

  def link_to_sheet(sheet)
    "<a href=\"#{h(Rails.application.routes.url_helpers.signup_sheet_url(sheet))}\">#{h(sheet.title)}</a>"
  end

  def simple_format(text)
    text.to_s.split(/\n{2,}/).map { |paragraph| "<p>#{h(paragraph.strip).gsub("\n", "<br>")}</p>" }.join
  end
end
