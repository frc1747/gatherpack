module MyGatherpack
  # What one person did for the team in a season, from their own records
  # only (spec §7a): events they checked in at or signed up for and were
  # marked done at, by kind of event, and meetings from check-ins and time
  # clock punches; and which checklist items covering them count each.
  #
  # Whether something counts is the person's own answer, from their stored
  # checklist results, whoever is looking: an item counts for them unless
  # they're exempt from it. Which items are named follows the viewer: only
  # those the viewer's status_for shows. A check-in counts when a count item
  # counts check-ins at its event type, or counts sign-ups on a sheet (or a
  # position on it) where the person has a sign-up at that event (§6.4). A
  # sign-up marked done at an event they didn't check in at counts by its
  # sheet or position only. Either way only events of the item's commitment
  # team or a team below it, during the commitment's period, count, as in
  # Commitments::CheckinSource and SignupSource.
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

    # Where one count source's items count: events of these teams (the
    # commitment's team and those below it) during the commitment's period.
    Reach = Struct.new(:item_ids, :team_ids, :times, keyword_init: true) do
      def covers?(team_id, start_time)
        team_ids.include?(team_id) && times.cover?(start_time)
      end
    end

    # One kind of event the person checked in at, or Meetings. key is the
    # event type's neat id, or MEETINGS. hours is nil when none of its
    # events has set times. item_ids are the checklist items covering the
    # person that count any of its events; uncounted is the KindRow of its
    # events none counts, or nil.
    KindRow = Struct.new(:key, :name, :events, :hours, :item_ids, :uncounted, keyword_init: true) do
      def meetings?
        key == MEETINGS
      end

      def counted?
        item_ids.any?
      end
    end

    # A section of "What you've done": one kind of event and its lines,
    # newest first. row is the kind's KindRow (from check-ins), nil when the
    # person only signed up at events of that kind.
    DoneSection = Struct.new(:key, :name, :lines, :row, keyword_init: true) do
      def events
        lines.size
      end

      # Hours at its timed events, or nil when none had set times.
      def hours
        found = lines.filter_map(&:hours)
        found.sum if found.any?
      end
    end

    # An event in a section. how is :checked_in, or :signed_up for a
    # sign-up marked done at an event the person didn't check in at. hours
    # is nil for an all-day event (Activity.all_day?), always.
    # item_ids are the checklist items covering the person that count it.
    # record is what its name links to: the Event when the viewer may open
    # it, else the sign-up's sheet, or nil for no link.
    DoneLine = Struct.new(:event, :how, :hours, :item_ids, :record, keyword_init: true)

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
        new(person, season: season, meetings: false).uncounted
      end

      # end_time − start_time for a timed event (Event#hours); nil for
      # all-day and TBA ones, whose times are only their day.
      def event_hours(event)
        event.hours if event.timed? && event.complete? && !all_day?(event)
      end

      # An all_day event, or a timed one that runs from midnight to the end
      # of a day, as events saved before time_kind existed and imported
      # whole-day events do.
      def all_day?(event)
        return true if event.all_day?
        return false unless event.timed? && event.complete?

        starts = event.start_time.in_time_zone
        ends = event.end_time.in_time_zone
        starts == starts.beginning_of_day && ends > starts &&
          (ends == ends.beginning_of_day || ends.seconds_since_midnight >= 1.day - 1.minute)
      end
    end

    attr_reader :person, :viewer, :season

    # +viewer_events+ is the viewer's policy_scope(Event); without it no
    # event is linked. meetings: false leaves meetings out without reading
    # punches or meetings held, for callers that never show them (Home).
    def initialize(person, season: Season.current, viewer: person, viewer_events: nil, meetings: true)
      @person = person
      @viewer = viewer
      @season = season
      @viewer_events = viewer_events
      @meetings = meetings
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
        meetings = build_meetings_row
        meetings ? [ meetings ] + rows : rows
      end
    end

    def kind_row(key)
      kind_rows.find { |row| row.key == key }
    end

    # The labels of a KindRow's or DoneLine's counting items that the
    # viewer's status_for shows; empty when it shows none of them.
    def counts_toward(row)
      row.item_ids.filter_map { |id| visible_labels[id] }.uniq
    end

    # Own only, while time tracking is on.
    def meetings?
      @meetings && own? && GatherPack::Features.enabled?(:time_tracking)
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

    # The Meetings KindRow, or nil when meetings aren't shown or there are none.
    def meetings_row
      kind_rows.find(&:meetings?)
    end

    # Events outside meetings the person checked in at, or signed up for
    # and was marked done at, as DoneSections by kind of event name.
    # Forms and punches aren't in it.
    def done_sections
      @done_sections ||= begin
        checked = event_checkins
        signed = done_signups
        reachable = reachable_event_ids(checked.map(&:event_id) + signed.map { |signup| signup.event.id })
        lines = checked.map { |checkin| checkin_line(checkin.event, reachable) } + signed.map { |signup| signup_line(signup, reachable) }
        rows = kind_rows.index_by(&:key)
        lines.group_by { |line| line.event.event_type }.map do |type, found|
          DoneSection.new(key: type.neat_id, name: type.name, row: rows[type.neat_id],
            lines: found.sort_by { |line| [ -line.event.start_time.to_f, line.event.name.to_s ] })
        end.sort_by { |section| section.name.to_s.downcase }
      end
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

    # This season and each earlier one holding any of the person's records, newest first.
    def seasons
      times = shown_checkins_scope.pluck("events.start_time")
      times += own_punches.pluck(:start_time) if meetings?
      times += fulfilled_signups.pluck("events.start_time") if GatherPack::Features.enabled?(:signups)
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

    def build_meetings_row
      return unless meetings? && (punches.any? || meetings_held.any? || meeting_checkins.any?)

      KindRow.new(key: MEETINGS, name: "Meetings", events: meetings_attended, hours: meeting_hours,
        item_ids: coverage[:meetings])
    end

    def kind_row_for(type, checkins)
      counting = checkins.index_with { |checkin| checkin_item_ids(checkin.event) }
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
    # { event_types: { type id => [Reach] }, events: { event id => item ids }, meetings: item ids }.
    # events holds the sheet and position items counting the person's own
    # sign-ups at each event in the season, checked in at or not, within
    # each item's reach.
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
      sources = CommitmentSource.where(commitment_id: ids.keys, kind: TYPE_SOURCES + SHEET_SOURCES).includes(:commitment).to_a
      return if sources.empty?

      reaches = reaches_for(sources.map(&:commitment).uniq, ids)
      sources.select { |source| TYPE_SOURCES.include?(source.kind) }.each do |source|
        found[:event_types][source.subject_id] += [ reaches[source.commitment_id] ]
      end

      sheet_sources = sources.select { |source| SHEET_SOURCES.include?(source.kind) }
      return if sheet_sources.empty?

      # The person's own sign-ups at events in the season: those they
      # checked in at, and those marked done where they didn't.
      places = Signup.counted.where(on_behalf_of_id: person.id).joins(signup_slot: %i[ signup_position event ])
        .where(events: { start_time: season.times })
        .pluck("signup_slots.event_id", "events.team_id", "events.start_time", "signup_positions.signup_sheet_id", "signup_slots.signup_position_id")
      places.each do |event_id, team_id, start_time, sheet_id, position_id|
        sheet_sources.each do |source|
          reach = reaches[source.commitment_id]
          next unless [ sheet_id, position_id ].include?(source.subject_id) && reach.covers?(team_id, start_time)

          found[:events][event_id] += reach.item_ids
        end
      end
    end

    # { commitment id => Reach }, from one read of the team tree.
    def reaches_for(commitments, ids)
      children = Team.pluck(:id, :parent_id).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(id, parent_id), found|
        found[parent_id] << id if parent_id
      end
      commitments.to_h do |commitment|
        [ commitment.id, Reach.new(item_ids: ids[commitment.id], team_ids: team_and_below(commitment.team_id, children), times: commitment.period_times) ]
      end
    end

    def team_and_below(team_id, children)
      found = Set.new
      pending = [ team_id ]
      while (id = pending.pop)
        pending.concat(children[id]) if found.add?(id)
      end
      found
    end

    # The items counting the person's check-in at the event: those counting
    # check-ins at its type, and those counting their sign-ups there.
    def checkin_item_ids(event)
      by_type = coverage[:event_types][event.event_type_id].select { |reach| reach.covers?(event.team_id, event.start_time) }
      (by_type.flat_map(&:item_ids) + coverage[:events][event.id]).uniq
    end

    # { item id => label } for every item the viewer's status_for shows.
    def visible_labels
      @visible_labels ||= checklists.flat_map { |_checklist, status| status.all_items }
        .select(&:item).to_h { |entry| [ entry.item.id, entry.item.label ] }
    end

    def checkin_line(event, reachable)
      DoneLine.new(event: event, how: :checked_in, hours: self.class.event_hours(event), item_ids: checkin_item_ids(event),
        record: (event if reachable.include?(event.id)))
    end

    # A sign-up at an event the person didn't check in at counts toward the
    # items counting their sign-ups there; check-in sources don't count it.
    def signup_line(signup, reachable)
      event = signup.event
      DoneLine.new(event: event, how: :signed_up, hours: self.class.event_hours(event), item_ids: coverage[:events][event.id],
        record: reachable.include?(event.id) ? event : signup.signup_sheet)
    end

    # Fulfilled sign-ups in the season outside meetings, on sheets the
    # viewer may see, at events the person didn't check in at; one per event.
    def done_signups
      return [] unless GatherPack::Features.enabled?(:signups)

      checked = checkins.map(&:event_id).to_set
      signups = fulfilled_signups.where(events: { start_time: season.times, time_clock_period_id: nil })
        .includes(signup_slot: [ { event: :event_type }, { signup_position: :signup_sheet } ]).to_a
        .reject { |signup| checked.include?(signup.event.id) }
      visible = visible_sheet_ids(signups.map { |signup| signup.signup_sheet.id })
      signups.select { |signup| visible.include?(signup.signup_sheet.id) }.uniq { |signup| signup.event.id }
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
