module Commitments
  # Credit from sign-ups on a sheet: one record per sign-up, to the person
  # it's on behalf of, quantity 1 for people and item positions alike
  # (bringing 3 pizzas is one contribution). Active sign-ups are planned and
  # fulfilled ones confirmed; cancelled and no-show sign-ups count nothing.
  # Only events of the commitment's team and those below it, during the
  # commitment's period, count. Dedupe key: the event, as for check-ins, so
  # a check-in at an event someone signed up for counts once.
  #
  # SignupPositionSource is the same kind narrowed to one position.
  class SignupSource < SourceKind
    STATES = { "active" => :planned, "fulfilled" => :confirmed }.freeze

    def self.label
      "Sign-ups"
    end

    def self.subject_type
      "SignupSheet"
    end

    # Sheets the person also organizes (spec §4.5), leaving out archived ones.
    def self.subject_choices(_commitment, person)
      SignupSheet.where(id: organized_sheet_ids(person)).order(:title)
    end

    # Whoever runs the subject's sheet, archived or not, so a source can
    # still be changed after its sheet is archived at the end of a season.
    def self.subject_allowed?(_commitment, person, subject)
      subject.is_a?(subject_type.constantize) && sheet_of(subject).organizer?(person)
    end

    def self.sheet_of(subject)
      subject
    end

    # The sheets that aren't archived that the person runs: those they're
    # listed on or whose team they manage, checked with SignupSheet#organizer?.
    def self.organized_sheet_ids(person)
      return [] if person.nil?
      return SignupSheet.visible.ids if person.admin?

      listed = SignupSheetOrganizer.where(person_id: person.id).select(:signup_sheet_id)
      candidates = SignupSheet.visible.where(id: listed).or(SignupSheet.visible.where(team_id: person.all_managed_teams.select(:id)))
      candidates.includes(:team).select { |sheet| sheet.organizer?(person) }.map(&:id)
    end

    def self.watches
      %w[ signup_changed.gatherpack signup_sheet_changed.gatherpack ]
    end

    def records(person_ids)
      Signup.where(on_behalf_of_id: person_ids, status: STATES.keys, signup_slot_id: slots.select(:id))
        .includes(signup_slot: %i[ event signup_position ]).map do |signup|
          event = signup.event
          CreditRecord.new(person_id: signup.on_behalf_of_id, quantity: 1, state: STATES.fetch(signup.status), date: event.start_time.to_date,
            dedupe_key: Commitments.event_key(event.id, signup.person_id), label: "#{signup.signup_position.name}: #{event.name}", link: sheet)
        end
    end

    # The upcoming dates with a place still free, while the sheet is open.
    def how_to_earn
      HowToEarn.new(text: "Sign up on #{sheet&.title}", links: open_dates)
    end

    def sheet
      source.subject
    end

    private

    # The subject's slots at events that count.
    def slots
      SignupSlot.where(signup_position_id: positions.select(:id), event_id: events.select(:id))
    end

    def positions
      SignupPosition.where(signup_sheet_id: source.subject_id)
    end

    def events
      Event.where(team_id: commitment.team_and_below_ids, start_time: commitment.period_times)
    end

    def open_dates
      return [] unless sheet&.open?

      upcoming = slots.where(disabled: false).joins(:event).where(events: { start_time: Time.current.. })
        .includes(:event, :signup_position).order("events.start_time").to_a
      upcoming.reject(&:full?).map(&:event).uniq.first(5).map do |event|
        [ "#{event.name}, #{event.start_time.strftime("%a %b %-d")}",
          Rails.application.routes.url_helpers.signup_sheet_path(sheet, anchor: ActionView::RecordIdentifier.dom_id(event)) ]
      end
    end
  end
end
