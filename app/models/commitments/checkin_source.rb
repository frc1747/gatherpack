module Commitments
  # Credit from check-ins: one record, quantity 1, per check-in at an event
  # of the source's event type, held by the commitment's team or a team
  # below it, during the commitment's period. The credit goes to the person
  # checked in. A check-in at an event that hasn't started yet is planned;
  # once it has started, confirmed. Dedupe key: the event.
  class CheckinSource < SourceKind
    def self.label
      "Check-ins"
    end

    def self.subject_type
      "EventType"
    end

    # Any event type: only events of the commitment's team and those below it
    # count, and those are within reach of everyone who runs the commitment.
    def self.subject_choices(_commitment, _person)
      EventType.order(:name)
    end

    def records(person_ids)
      now = Time.current
      Checkin.where(person_id: person_ids, event_id: events.select(:id)).includes(:event).map do |checkin|
        event = checkin.event
        CreditRecord.new(person_id: checkin.person_id, quantity: 1, state: event.start_time > now ? :planned : :confirmed, date: event.start_time.to_date,
          dedupe_key: Commitments.event_key(event.id, checkin.person_id), label: "Checked in: #{event.name}", link: event)
      end
    end

    def how_to_earn
      upcoming = events.where(start_time: Time.current..).order(:start_time).limit(5).map do |event|
        [ "#{event.name}, #{event.start_time.strftime("%a %b %-d")}", event ]
      end
      HowToEarn.new(text: "Check in at any #{source.subject&.name} event", links: upcoming)
    end

    private

    def events
      Event.where(event_type_id: source.subject_id, team_id: commitment.team_and_below_ids, start_time: commitment.period_times)
    end
  end
end
