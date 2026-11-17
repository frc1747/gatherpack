# Prepended to SignupNotices from config/initializers/phone_notifications_connectors.rb.
# Reminders and change notices also go to the phones of the people they email.
# A confirmation (the person just acted) and an organizer's message (free
# text) don't. The emails are queued first, and a failure here can't stop them.
module SignupNoticesPushConnector
  def reminder(signup)
    result = super
    push_to_emailed("Reminder: #{signup_label(signup)}") { signup.signup_sheet }
    result
  end

  def event_changed(event, start_time_was:, end_time_was:)
    result = super
    sheets = nil
    push_to_emailed("Time changed: #{event.name}") do |person|
      sheets ||= sheets_by_person(event)
      sheets[person].first
    end
    result
  end

  def cancelled(signup, by:)
    result = super
    push_to_emailed("Sign-up cancelled: #{signup_label(signup)}") { signup.signup_sheet }
    result
  end

  def moved(signup, from:, by:)
    result = super
    push_to_emailed("Sign-up moved: #{signup_label(signup)}") { signup.signup_sheet }
    result
  end

  private
    # Remembers who the last batch of emails went to.
    def deliver(people, subject)
      @emailed_people = []
      count = super
      @emailed_people = people.compact.uniq.select { |person| person.user&.email.present? } if count.positive?
      count
    end

    def signup_label(signup)
      "#{signup.signup_position.name}, #{signup.event.name}"
    end

    # The block gives the sheet to open for a person.
    def push_to_emailed(title)
      return unless GatherPack::PushChannel.available?

      @emailed_people.each do |person|
        path = Rails.application.routes.url_helpers.signup_sheet_path(yield(person))
        GatherPack::PushChannel.deliver(person, topic: :shifts, title: title, path: path)
      end
    rescue StandardError => e
      Rails.logger.error("Sign-up phone notifications failed: #{e.class}: #{e.message}")
    end

    def sheets_by_person(event)
      Signup.active.joins(:signup_slot).where(signup_slots: { event_id: event.id })
        .includes(:person, :signed_up_by, :on_behalf_of, signup_slot: { signup_position: :signup_sheet })
        .each_with_object(Hash.new { |hash, person| hash[person] = [] }) do |signup, map|
          recipients(signup).compact.each { |person| map[person] |= [ signup.signup_sheet ] }
        end
    end
end
