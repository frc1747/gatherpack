module MyGatherpack
  # What one person did in a season, from their own records only (spec §7a):
  # check-ins, time clock punches, fulfilled sign-ups and submitted forms,
  # and which checklist items covering them count each kind of event.
  #
  # The viewer is the person or a guardian of theirs. A guardian gets no
  # punches (they stay out for guardians, as on the family page), reads the
  # person's checklists as status_for shows them to the guardian, and a
  # record's event carries a link only when the viewer's own event scope
  # already includes it. Each block reads its records in one query.
  class Activity
    MEETINGS = "meetings".freeze
    ATTENDANCE = "attendance".freeze
    COUNT = "count".freeze

    # Check-in sources count by event type; sign-up sources by sheet, and
    # through the sheet's events.
    TYPE_SOURCES = %w[checkins].freeze
    SHEET_SOURCES = %w[signups signup_positions].freeze

    # A row of "By kind of event". key is the event type's neat id, or
    # MEETINGS. hours is nil when none of its events has set times.
    # counts_toward holds the labels of the covering items that count it.
    KindRow = Struct.new(:key, :name, :events, :hours, :counts_toward, keyword_init: true) do
      def meetings?
        key == MEETINGS
      end

      def counted?
        counts_toward.any?
      end
    end

    # A line of History. kind_key matches a KindRow's key (nil for forms).
    # record is what the line is about, for its link: an Event the viewer
    # may open, a SignupSheet or a FormResponse; nil for no link.
    Entry = Struct.new(:at, :title, :detail, :how, :hours, :kind_key, :record, keyword_init: true)

    class << self
      def enabled?
        MyGatherpack.enabled? && GatherPack::Features.enabled?(:my_gatherpack_activity)
      end

      # The event types the person checked in at in the season that no
      # checklist item covering them counts, as KindRows (event count and
      # hours). Home's "Also this season" and the activity page's "Not
      # required for you" rows both come from here. Meetings are never in
      # it: attendance covers them.
      def uncounted(person, season)
        new(person, season: season).uncounted
      end

      # end_time − start_time for a timed event (Event#hours); nil for
      # all-day and TBA ones, whose times are only their day.
      def event_hours(event)
        event.hours if event.timed? && event.complete?
      end
    end

    attr_reader :person, :viewer, :season

    # +viewer_events+ is the viewer's policy_scope(Event); without it no
    # event is linked.
    def initialize(person, season: Season.current, viewer: person, viewer_events: nil)
      @person = person
      @viewer = viewer
      @season = season
      @viewer_events = viewer_events
    end

    def own?
      viewer.id == person.id
    end

    def uncounted
      kind_rows.reject { |row| row.meetings? || row.counted? }
    end

    # Meetings first, then event types by name.
    def kind_rows
      @kind_rows ||= begin
        rows = event_checkins.group_by { |checkin| checkin.event.event_type }.map do |type, checkins|
          events = checkins.map(&:event)
          counts = (coverage[:event_types][type.id] + events.flat_map { |event| coverage[:events][event.id] }).uniq
          KindRow.new(key: type.neat_id, name: type.name, events: events.size, hours: total_hours(events), counts_toward: counts)
        end.sort_by { |row| row.name.to_s.downcase }
        meetings_row ? [ meetings_row ] + rows : rows
      end
    end

    def kind_row(key)
      kind_rows.find { |row| row.key == key }
    end

    # Own only, while time tracking is on.
    def meetings?
      own? && GatherPack::Features.enabled?(:time_tracking)
    end

    def meeting_hours
      punches.sum { |punch| punch_hours(punch).to_f }
    end

    # Meetings that have ended, on the person's teams.
    def meetings_held
      return [] unless meetings?

      @meetings_held ||= Event.where.not(time_clock_period_id: nil).where(start_time: season.times)
        .where(end_time: ...Time.current).where(team_id: person.all_teams.select(:id)).to_a
    end

    # Held meetings the person checked in at or was clocked in during.
    def meetings_attended
      checked = meeting_checkins.map(&:event_id).to_set
      meetings_held.count do |meeting|
        checked.include?(meeting.id) || punches.any? { |punch| overlaps?(punch, meeting) }
      end
    end

    def event_count
      event_checkins.size
    end

    # Hours at timed events outside meetings, or nil when none had set times.
    def event_hours
      total_hours(event_checkins.map(&:event))
    end

    # The person's attendance items, as the viewer may see them: a ward's
    # page shows these in place of meeting hours.
    def attendance_items
      checklists.flat_map { |_checklist, status| status.all_items.select { |entry| entry.item&.kind == ATTENDANCE } }
    end

    # [[checklist, Checklists::Status], ...] covering the person, as the viewer may see them.
    def checklists
      @checklists ||= Checklists.enabled? ? Checklists.checklist_for(person, viewer: viewer) : []
    end

    # Newest first; with +kind+ (a KindRow key) only that kind's lines.
    def history(kind = nil)
      entries = checkin_entries + punch_entries + signup_entries + form_entries
      entries = entries.select { |entry| entry.kind_key == kind } if kind.present?
      entries.sort_by { |entry| [ -entry.at.to_f, entry.title.to_s ] }
    end

    # This season and each earlier one holding any of the person's records, newest first.
    def seasons
      times = Checkin.where(person_id: person.id).joins(:event).pluck("events.start_time")
      times += own_punches.pluck(:start_time) if meetings?
      times += fulfilled_signups.pluck("events.start_time") if GatherPack::Features.enabled?(:signups)
      times += submissions.pluck(:submitted_at) if GatherPack::Features.enabled?(:forms)
      found = times.compact.map { |time| Season.containing(time.in_time_zone.to_date) }
      current = Season.current
      (found.select { |found_season| found_season < current } + [ current, season ]).uniq.sort.reverse
    end

    private

    def checkins
      @checkins ||= Checkin.where(person_id: person.id).joins(:event).merge(Event.where(start_time: season.times))
        .includes(event: :event_type).to_a
    end

    def event_checkins
      checkins.reject { |checkin| checkin.event.time_clock_period_id }
    end

    def meeting_checkins
      checkins.select { |checkin| checkin.event.time_clock_period_id }
    end

    def punches
      return [] unless meetings?

      @punches ||= own_punches.where(start_time: season.times).includes(:time_clock_period).to_a
    end

    # TimeClockPunchPolicy::Scope always includes a person's own punches; a
    # person with no login has only those.
    def own_punches
      own = TimeClockPunch.where(person_id: person.id)
      person.user ? TimeClockPunchPolicy::Scope.new(person.user, TimeClockPunch).resolve.merge(own) : own
    end

    def meetings_row
      return unless meetings? && (punches.any? || meetings_held.any? || meeting_checkins.any?)

      KindRow.new(key: MEETINGS, name: "Meetings", events: meetings_attended, hours: meeting_hours, counts_toward: coverage[:meetings])
    end

    # The labels of the items covering the person that count things:
    # { event_types: { id => labels }, events: { id => labels }, meetings: labels }.
    # An exempt item doesn't count anything for them.
    def coverage
      @coverage ||= begin
        found = { event_types: Hash.new { [] }, events: Hash.new { [] }, meetings: [] }
        entries = checklists.flat_map { |_checklist, status| status.all_items.reject(&:exempt?) }
        found[:meetings] = entries.select { |entry| entry.item&.kind == ATTENDANCE }.map { |entry| entry.item.label }.uniq
        add_count_coverage(found, entries.map(&:item).select { |item| item&.kind == COUNT && item.respond_to?(:commitment_id) && item.commitment_id })
        found
      end
    end

    def add_count_coverage(found, items)
      return if items.empty?

      labels = items.group_by(&:commitment_id).transform_values { |list| list.map(&:label) }
      sources = CommitmentSource.where(commitment_id: labels.keys, kind: TYPE_SOURCES + SHEET_SOURCES).to_a
      sources.select { |source| TYPE_SOURCES.include?(source.kind) }.each do |source|
        found[:event_types][source.subject_id] += labels[source.commitment_id]
      end

      sheets = sheet_labels(sources.select { |source| SHEET_SOURCES.include?(source.kind) }, labels)
      return if sheets.empty?

      SignupSheetEvent.where(signup_sheet_id: sheets.keys, event_id: checkins.map(&:event_id)).pluck(:signup_sheet_id, :event_id).each do |sheet_id, event_id|
        found[:events][event_id] += sheets[sheet_id]
      end
    end

    # { sheet_id => labels } for sign-up sources, a position's by its sheet.
    def sheet_labels(sources, labels)
      positions = SignupPosition.where(id: sources.select { |source| source.subject_type == "SignupPosition" }.map(&:subject_id)).pluck(:id, :signup_sheet_id).to_h
      sources.each_with_object(Hash.new { [] }) do |source, sheets|
        sheet_id = source.subject_type == "SignupPosition" ? positions[source.subject_id] : source.subject_id
        sheets[sheet_id] += labels[source.commitment_id] if sheet_id
      end
    end

    def checkin_entries
      reachable = reachable_event_ids(checkins.map(&:event_id))
      checkins.map do |checkin|
        event = checkin.event
        Entry.new(at: event.start_time, title: event.name, detail: [ event.event_type.name, event.location.presence ].compact.join(" · "),
          how: "Checked in", hours: self.class.event_hours(event), kind_key: event.time_clock_period_id ? MEETINGS : event.event_type.neat_id,
          record: (event if reachable.include?(event.id)))
      end
    end

    def punch_entries
      punches.map do |punch|
        Entry.new(at: punch.start_time, title: punch.time_clock_period&.name.presence || "Time clock", detail: nil,
          how: punch.end_time ? "Time clock" : "Time clock, still clocked in", hours: punch_hours(punch), kind_key: MEETINGS)
      end
    end

    # Fulfilled sign-ups on sheets the viewer may see. One at an event the
    # person also checked in at is that check-in's line.
    def signup_entries
      return [] unless GatherPack::Features.enabled?(:signups)

      checked = checkins.map(&:event_id).to_set
      signups = fulfilled_signups.where(events: { start_time: season.times })
        .includes(signup_slot: [ { event: :event_type }, { signup_position: :signup_sheet } ]).to_a
        .reject { |signup| checked.include?(signup.event.id) }
      visible = signups.map(&:signup_sheet).uniq.select { |sheet| SignupSheetPolicy.new(viewer.user, sheet).show? }.to_set

      signups.select { |signup| visible.include?(signup.signup_sheet) }.map do |signup|
        event = signup.event
        Entry.new(at: event.start_time, title: signup.signup_position.name, detail: [ event.name, signup.signup_sheet.title ].uniq.join(" · "),
          how: "Signed up, marked done", hours: self.class.event_hours(event), kind_key: event.event_type.neat_id, record: signup.signup_sheet)
      end
    end

    def fulfilled_signups
      signups = Signup.fulfilled.joins(signup_slot: :event)
      signups.where(person_id: person.id).or(signups.where(on_behalf_of_id: person.id))
    end

    # Submitted forms the viewer may read, by FormAccess as on the forms pages.
    def form_entries
      return [] unless GatherPack::Features.enabled?(:forms)

      found = submissions.where(submitted_at: season.times).includes(form_response: :form).to_a
      readable = found.map { |submission| submission.form_response.form }.uniq.select { |form| FormAccess.new(viewer, person, form).can_read? }.to_set
      found.select { |submission| readable.include?(submission.form_response.form) }.map do |submission|
        Entry.new(at: submission.submitted_at, title: submission.form_response.form.title, how: "Form submitted", record: submission.form_response)
      end
    end

    def submissions
      FormSubmission.joins(:form_response).where(form_responses: { subject_id: person.id })
        .where(status: %i[pending active superseded]).where.not(submitted_at: nil)
    end

    def reachable_event_ids(ids)
      return Set.new if @viewer_events.nil? || ids.empty?

      @viewer_events.where(id: ids).pluck(:id).to_set
    end

    def total_hours(events)
      hours = events.filter_map { |event| self.class.event_hours(event) }
      hours.sum if hours.any?
    end

    def punch_hours(punch)
      (punch.end_time - punch.start_time) / 1.hour if punch.end_time && punch.start_time
    end

    def overlaps?(punch, meeting)
      punch.start_time < meeting.end_time && (punch.end_time.nil? || punch.end_time > meeting.start_time)
    end
  end
end
