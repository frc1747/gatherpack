module MyGatherpack
  # What one person did in a season, from their own records only (spec §7a):
  # check-ins, time clock punches, fulfilled sign-ups and submitted forms,
  # and which checklist items covering them count each kind of event.
  #
  # Whether something counts is the person's own answer, from their stored
  # checklist results, whoever is looking: an item counts for them unless
  # they're exempt from it. Which items are named follows the viewer: only
  # those the viewer's status_for shows. A check-in counts when a count item
  # counts check-ins at its event type, or counts sign-ups on a sheet (or a
  # position on it) where the person has a sign-up at that event (§6.4).
  #
  # The viewer is the person or a guardian of theirs. A guardian gets no
  # punches and no meetings (they stay out for guardians), and a record's
  # event carries a link only when the viewer's own event scope already
  # includes it. Each block reads its records in one query.
  class Activity
    MEETINGS = "meetings".freeze
    ATTENDANCE = "attendance".freeze
    COUNT = "count".freeze

    # Check-in sources count by event type; sign-up sources by sheet or
    # position, through the person's own sign-ups.
    TYPE_SOURCES = %w[checkins].freeze
    SHEET_SOURCES = %w[signups signup_positions].freeze

    # A row of "By kind of event". key is the event type's neat id, or
    # MEETINGS. hours is nil when none of its events has set times.
    # item_ids are the checklist items covering the person that count any
    # of its events; uncounted is the KindRow of its events none counts,
    # or nil.
    KindRow = Struct.new(:key, :name, :events, :hours, :item_ids, :uncounted, keyword_init: true) do
      def meetings?
        key == MEETINGS
      end

      def counted?
        item_ids.any?
      end
    end

    # A line of History. kind_key matches a KindRow's key (nil for forms).
    # record is what the line is about, for its link: an Event the viewer
    # may open, a SignupSheet or a FormResponse; nil for no link.
    Entry = Struct.new(:at, :title, :detail, :how, :hours, :kind_key, :record, keyword_init: true)

    # FormAccess for one form of several, sharing one viewer–subject
    # pair's lookups (AudienceAccess memoizes them per instance), so History
    # makes them once rather than per form. A submission means a response,
    # which is all reading needs of the audience, so that isn't asked.
    class SharedFormAccess < FormAccess
      def initialize(pair, form)
        super(pair.viewer, pair.subject, form, in_audience: false, has_response: true)
        @pair = pair
      end

      def component?(component)
        @pair.component?(component)
      end

      private

      def subject_team_ids
        @pair.send(:subject_team_ids)
      end

      def viewer_badge_ids
        @pair.send(:viewer_badge_ids)
      end
    end

    class << self
      def enabled?
        MyGatherpack.enabled? && GatherPack::Features.enabled?(:my_gatherpack_activity)
      end

      # The event types the person checked in at in the season, with only
      # the check-ins no checklist item covering them counts, as KindRows
      # (event count and hours). Home's "Also this season" and the activity
      # page's "Not required" rows both come from here. Meetings are never
      # in it: attendance covers them.
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
      kind_rows.filter_map(&:uncounted)
    end

    # Meetings first, then event types by name.
    def kind_rows
      @kind_rows ||= begin
        rows = event_checkins.group_by { |checkin| checkin.event.event_type }.map do |type, checkins|
          kind_row_for(type, checkins)
        end.sort_by { |row| row.name.to_s.downcase }
        meetings_row ? [ meetings_row ] + rows : rows
      end
    end

    def kind_row(key)
      kind_rows.find { |row| row.key == key }
    end

    # The labels of the row's counting items that the viewer's status_for
    # shows; empty when it shows none of them.
    def counts_toward(row)
      row.item_ids.filter_map { |id| visible_labels[id] }.uniq
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

    # The person's own active sign-ups still to come, soonest first, on
    # sheets the viewer may see.
    def upcoming_signups
      return [] unless GatherPack::Features.enabled?(:signups)

      @upcoming_signups ||= begin
        signups = Signup.active.joins(signup_slot: :event).merge(Event.upcoming)
        found = signups.where(person_id: person.id).or(signups.where(on_behalf_of_id: person.id))
          .includes(signup_slot: [ :event, { signup_position: :signup_sheet } ]).to_a
        visible = visible_sheet_ids(found.map { |signup| signup.signup_sheet.id })
        found.select { |signup| visible.include?(signup.signup_sheet.id) }.sort_by { |signup| [ signup.event.start_time, signup.signup_sheet.title ] }
      end
    end

    # Newest first; with +kind+ (a KindRow key) only that kind's lines.
    def history(kind = nil)
      entries = checkin_entries + punch_entries + signup_entries + form_entries
      entries = entries.select { |entry| entry.kind_key == kind } if kind.present?
      entries.sort_by { |entry| [ -entry.at.to_f, entry.title.to_s ] }
    end

    # This season and each earlier one holding any of the person's records, newest first.
    def seasons
      times = shown_checkins_scope.pluck("events.start_time")
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

    # A guardian sees no meetings at all (§7a.4).
    def shown_checkins
      own? ? checkins : event_checkins
    end

    def shown_checkins_scope
      scope = Checkin.where(person_id: person.id).joins(:event)
      own? ? scope : scope.where(events: { time_clock_period_id: nil })
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

      @meetings_row ||= KindRow.new(key: MEETINGS, name: "Meetings", events: meetings_attended, hours: meeting_hours,
        item_ids: coverage[:meetings])
    end

    def kind_row_for(type, checkins)
      by_type = coverage[:event_types][type.id]
      counting = checkins.index_with { |checkin| (by_type + coverage[:events][checkin.event_id]).uniq }
      left = checkins.select { |checkin| counting[checkin].empty? }
      events = checkins.map(&:event)
      uncounted = if left.any?
        KindRow.new(key: type.neat_id, name: type.name, events: left.size, hours: total_hours(left.map(&:event)), item_ids: [])
      end
      KindRow.new(key: type.neat_id, name: type.name, events: events.size, hours: total_hours(events),
        item_ids: counting.values.flatten.uniq, uncounted: uncounted)
    end

    # The person's own answer, from their stored results with no viewer
    # filter: the ids of the count and attendance items covering them, on
    # checklists in force, that they aren't exempt from, as
    # { event_types: { type id => item ids }, events: { event id => item ids }, meetings: item ids }.
    def coverage
      @coverage ||= begin
        found = { event_types: Hash.new { [] }, events: Hash.new { [] }, meetings: [] }
        items = Checklists.enabled? ? covering_items : []
        found[:meetings] = items.select { |item| item.kind == ATTENDANCE }.map(&:id)
        add_count_coverage(found, items.select { |item| item.kind == COUNT && item.respond_to?(:commitment_id) && item.commitment_id })
        found
      end
    end

    def covering_items
      ChecklistItem.where(kind: [ COUNT, ATTENDANCE ], id: ChecklistResult.joins(:checklist).where(person_id: person.id)
        .where.not(item_id: nil).where.not(status: :exempt).where(checklists: { status: :active }).select(:item_id)).to_a
    end

    def add_count_coverage(found, items)
      return if items.empty?

      ids = items.group_by(&:commitment_id).transform_values { |list| list.map(&:id) }
      sources = CommitmentSource.where(commitment_id: ids.keys, kind: TYPE_SOURCES + SHEET_SOURCES).to_a
      sources.select { |source| TYPE_SOURCES.include?(source.kind) }.each do |source|
        found[:event_types][source.subject_id] += ids[source.commitment_id]
      end

      sheet_sources = sources.select { |source| SHEET_SOURCES.include?(source.kind) }
      return if sheet_sources.empty?

      # The person's own sign-ups at the events they checked in at.
      places = Signup.counted.where(on_behalf_of_id: person.id).joins(signup_slot: :signup_position)
        .where(signup_slots: { event_id: checkins.map(&:event_id) })
        .pluck("signup_slots.event_id", "signup_positions.signup_sheet_id", "signup_slots.signup_position_id")
      places.each do |event_id, sheet_id, position_id|
        sheet_sources.each do |source|
          found[:events][event_id] += ids[source.commitment_id] if [ sheet_id, position_id ].include?(source.subject_id)
        end
      end
    end

    # { item id => label } for every item the viewer's status_for shows.
    def visible_labels
      @visible_labels ||= checklists.flat_map { |_checklist, status| status.all_items }
        .select(&:item).to_h { |entry| [ entry.item.id, entry.item.label ] }
    end

    def checkin_entries
      reachable = reachable_event_ids(shown_checkins.map(&:event_id))
      shown_checkins.map do |checkin|
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
        .reject { |signup| checked.include?(signup.event.id) || (!own? && signup.event.time_clock_period_id) }
      visible = visible_sheet_ids(signups.map { |signup| signup.signup_sheet.id })

      signups.select { |signup| visible.include?(signup.signup_sheet.id) }.map do |signup|
        event = signup.event
        Entry.new(at: event.start_time, title: signup.signup_position.name, detail: [ event.name, signup.signup_sheet.title ].uniq.join(" · "),
          how: "Signed up, marked done", hours: self.class.event_hours(event), kind_key: event.event_type.neat_id, record: signup.signup_sheet)
      end
    end

    def fulfilled_signups
      signups = Signup.fulfilled.joins(signup_slot: :event)
      signups.where(person_id: person.id).or(signups.where(on_behalf_of_id: person.id))
    end

    # The ids among these sheets the viewer may see, in one pass of
    # SignupSheetPolicy::Scope narrowed to them.
    def visible_sheet_ids(ids)
      return Set.new if ids.empty? || viewer.user.nil?

      SignupSheetPolicy::Scope.new(viewer.user, SignupSheet.where(id: ids.uniq)).resolve.pluck(:id).to_set
    end

    # Submitted forms the viewer may read, by FormAccess as on the forms
    # pages, with the viewer–subject lookups made once for every form.
    def form_entries
      return [] unless GatherPack::Features.enabled?(:forms)

      found = submissions.where(submitted_at: season.times).includes(form_response: { form: :form_badge_grants }).to_a
      pair = AudienceAccess.new(viewer, person)
      readable = found.map { |submission| submission.form_response.form }.uniq.select { |form| SharedFormAccess.new(pair, form).can_read? }.to_set
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
