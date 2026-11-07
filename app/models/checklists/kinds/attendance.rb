module Checklists
  module Kinds
    # Attendance at meetings (spec §6.3). Meetings are events linked to a
    # time clock period that start within the item's dates and have ended.
    # The periods are those of the checklist's team and the teams below it,
    # and periods on no team, that overlap the dates, unless the item names
    # some (any of them). Only punches on those periods count, as on the
    # report Page this replaces.
    # Credit is punched time overlapping a meeting, merged, so leaving early
    # costs and staying late adds nothing. With extra hours counting, time
    # punched outside meetings makes up missed time in the same group, never
    # above 100%.
    #
    # Config: "rules" (rows from the item form's rules table,
    # checklist_items/_attendance_rules), "period_ids", and the settings
    # extra_hours_count and leeway_minutes. A rule is a share of meeting
    # hours over dates (its start a date or "within the last N", its end a
    # date; blank ends are the item's), optionally for every week on its
    # own, judged alone or counted together with other rules (a pool), and
    # judged only once enough meetings are held. Each meeting's hours count
    # toward a pool's minimum at its own rule's share. Nothing is built in:
    # no months, shares or pools.
    #
    # A manager can excuse a person from one meeting (a ChecklistExcuse with
    # an event): it leaves their required and credited hours.
    class Attendance < ItemKind
      RULE_FIELDS = %w[name starts ends_on share weekly with judge_after].freeze

      # A rule row from the config, its start resolved against the as-of
      # moment, with the pool it's judged in.
      Rule = Struct.new(:index, :name, :starts, :starts_on, :ends_on, :share, :weekly, :with, :judge_after, :pool, keyword_init: true) do
        def cover?(date, window)
          from = starts_on || window.starts_on
          to = ends_on || window.ends_on
          (from.nil? || date >= from) && (to.nil? || date <= to)
        end
      end

      # Rules judged together: key and label are the same for every rule in it.
      Pool = Struct.new(:key, :label, :rules, keyword_init: true) do
        def judge_after
          rules.map { |rule| rule.judge_after.to_i }.max
        end
      end

      class << self
        def label = "Attendance"
        def description = "Comes to enough meetings"
        def uses_dates? = true

        def settings
          [
            ItemKind::Setting.new(key: :extra_hours_count, type: :boolean,
              label: "Time outside meetings makes up missed meeting time",
              hint: "Within the same rule, or the same week for weekly rules. Never above 100%"),
            ItemKind::Setting.new(key: :leeway_minutes, type: :number, label: "Leeway (minutes)",
              hint: "Someone this close to a minimum passes. Blank: 1")
          ]
        end

        def form_partial = "checklist_items/attendance_rules"

        def form_params
          [ { period_ids: [] }, { rules: [ :name, :ends_on, :share, :weekly, :with, :judge_after, { starts: %i[mode date amount unit] } ] } ]
        end

        # Rows that are wholly blank are dropped. A share that isn't a whole
        # number is kept as typed, so validate can say so instead of
        # rounding it quietly.
        def normalize_form(params)
          rows = params["rules"]
          rows = rows.sort_by { |key, _| key.to_s.to_i }.map(&:last) if rows.is_a?(Hash)
          rules = Array(rows).map { |row| cast_rule(row.to_h.stringify_keys) }.select { |rule| rule_filled?(rule) }
          { "period_ids" => Array(params["period_ids"]).compact_blank.uniq, "rules" => rules }
        end

        def references = { "period_ids" => "TimeClockPeriod" }

        # Only admins and managers of the checklist's team (or a team above
        # it) set one up: it reads everyone's punches.
        def authorable_by?(item, author)
          item.checklist.present? && item.checklist.manager?(author)
        end

        # A result carries hours. In full (summary, detail, measures) it
        # shows to viewers who could see the person's punches in the app
        # (TimeClockPunchPolicy::Scope: an admin, a manager of a team
        # they're on, or the person), and to holders of a full grant on the
        # checklist that covers the item (admin-given, as the report Page
        # does). Anyone else the checklist lets see the item, guardians
        # included, sees only its status.
        def cap_levels(item, viewer, person_ids)
          return person_ids.index_with(:full) if viewer.nil? || viewer.user&.admin? || full_grant?(item, viewer)

          punch_people = [ viewer.id ]
          punch_people += viewer.all_managed_teams.flat_map(&:person_ids) if viewer.manager?
          person_ids.index_with { |id| punch_people.include?(id) ? :full : :status }
        end

        def copy_dates(item)
          rules(item).flat_map do |rule|
            starts = rule.starts unless rule.starts&.relative?
            [ [ "starts", "from", starts&.date ], [ "ends_on", "until", rule.ends_on ] ].filter_map do |field, word, date|
              { key: "rules.#{rule.index}.#{field}", label: "rule \u201C#{rule.name}\u201D #{word}", value: date } if date
            end
          end
        end

        def apply_copy_dates(_item, config, dates)
          rules = Array(config["rules"]).map(&:dup)
          dates.each do |key, date|
            _, index, field = key.split(".")
            row = rules[index.to_i] or next
            row[field] = field == "starts" ? RelativeDate.new(date: date).to_config : date.iso8601
          end
          config.merge("rules" => rules)
        end

        def invalidations
          [
            # A punch moved to someone else changes the old owner's result too.
            [ ::TimeClockPunch, ->(punch) { [ punch.person_id, punch.person_id_previously_was ].compact.uniq } ],
            [ ::Event, ->(_event) { :all } ],
            [ ::TimeClockPeriod, ->(_period) { :all } ]
          ]
        end

        def measures
          [
            ItemKind::Measure.new(key: :meetings, label: "Meetings attended", type: :number),
            ItemKind::Measure.new(key: :held, label: "Meetings held", type: :number),
            ItemKind::Measure.new(key: :credited, label: "Hours at meetings", type: :hours),
            ItemKind::Measure.new(key: :percent, label: "Attendance %", type: :percent),
            ItemKind::Measure.new(key: :extra, label: "Extra hours", type: :hours, owner_only: true)
          ]
        end

        # The item's rules, in order, each with its pool; a relative start
        # resolves against as_of. share is nil when it isn't a whole number.
        # Whether the viewer holds a full grant on the item's checklist that
        # covers the item (or the group it's in), by badge or team.
        def full_grant?(item, viewer)
          grants = ChecklistGrant.where(checklist_id: item.checklist_id, access: :full).to_a
          grants = grants.select { |grant| (grant.item_ids & [ item.id, item.parent_id ].compact).any? }
          return false if grants.empty?

          badge_ids = BadgeAssignment.where(person_id: viewer.id).pluck(:badge_id)
          team_ids = Checklists.team_ancestor_ids(Membership.where(person_id: viewer.id).pluck(:team_id))
          grants.any? { |grant| badge_ids.include?(grant.badge_id) || team_ids.include?(grant.team_id) }
        end

        def rules(item, as_of: Time.current)
          rules = Array((item.config || {})["rules"]).each_with_index.map do |row, index|
            starts = RelativeDate.from_config(row["starts"])
            Rule.new(index: index, name: row["name"].presence || "Rule #{index + 1}", starts: starts, starts_on: starts&.resolve(as_of),
              ends_on: parse_date(row["ends_on"]), share: whole_number(row["share"]), weekly: row["weekly"] == true,
              with: row["with"].to_s.strip.presence, judge_after: row["judge_after"].to_i)
          end
          assign_pools(rules)
          rules
        end

        def validate(item)
          rules = rules(item)
          return item.errors.add(:base, "Add at least one rule with a share of meeting hours") if rules.empty?

          names = rules.map(&:name)
          names.tally.each { |name, count| item.errors.add(:base, "Two rules are named #{name}") if count > 1 }
          rows = Array(item.config["rules"])
          rules.each do |rule|
            share = rows[rule.index]["share"]
            if share.blank?
              item.errors.add(:base, "#{rule.name} needs a share of meeting hours")
            elsif rule.share.nil?
              item.errors.add(:base, "#{rule.name}: the share must be a whole percent")
            elsif !(0..100).cover?(rule.share)
              item.errors.add(:base, "#{rule.name}: the share must be from 0 to 100%")
            end
            item.errors.add(:base, "#{rule.name} has an end date that isn't a date") if rows[rule.index]["ends_on"].present? && rule.ends_on.nil?
            item.errors.add(:base, "#{rule.name} ends before it starts") if rule.starts_on && rule.ends_on && rule.ends_on < rule.starts_on
            item.errors.add(:base, "#{rule.name} is counted together with #{rule.with}, but no other rule has that name") if rule.with && (rule.with == rule.name || names.exclude?(rule.with))
          end
          rules.map(&:pool).uniq.each do |pool|
            item.errors.add(:base, "Rules counted together must all be weekly, or none of them") if pool.rules.map(&:weekly).uniq.size > 1
          end
          item.errors.add(:base, "The leeway can't be negative") if item.config["leeway_minutes"].to_i.negative?
          validate_periods(item)
        end

        def problems(item)
          problems = missing_references(item)
          problems << "No rules yet" if rules(item).empty?
          if problems.empty? && item.checklist
            window = Window.for(item, Time.current, fallback: Window.for(item.checklist, Time.current))
            problems << "No time clock period covers the item's dates" unless periods(item, window).exists?
          end
          problems
        end

        # A meeting ending changes the answer with no data change; the next
        # one's end (just after, so it counts as held). A rule starting
        # "within the last N" moves at midnight.
        def next_change_at(item, context)
          window = context.window_for(item)
          ends = meetings_scope(item, window, upcoming: true).where("events.end_time >= ?", context.as_of).minimum(:end_time)
          times = [ ends && ends + 1.second ]
          times += rules(item, as_of: context.as_of).map { |rule| rule.starts&.next_change_at(context.as_of) }
          times.compact.min
        end

        def describe(item)
          rules = rules(item)
          return item.label if rules.empty?

          "At least " + rules.map { |rule| rule_sentence(rule) }.join("; ")
        end

        def period_ids(item)
          Array(item.config["period_ids"]).compact_blank.uniq
        end

        # Periods of the checklist's team and the teams below it, and
        # periods on no team.
        def team_periods(checklist)
          team_ids = Checklists.team_subtree_ids([ checklist.team_id ])
          TimeClockPeriod.where(team_id: nil).or(TimeClockPeriod.where(team_id: team_ids))
        end

        # The periods the item names (any of them), or the checklist's
        # periods overlapping the window.
        def periods(item, window)
          return team_periods(item.checklist).where(id: period_ids(item)) if period_ids(item).any?

          periods = team_periods(item.checklist)
          periods = periods.where(start_time: nil).or(periods.where(start_time: ..window.end_time.to_date))
          periods = periods.where(end_time: nil).or(periods.where(end_time: window.starts_on..)) if window.starts_on
          periods
        end

        # Meetings in the window's periods that start within it, ended or
        # not. upcoming: also those starting after the as-of moment.
        def meetings_scope(item, window, upcoming: false)
          scope = ::Event.where(time_clock_period_id: periods(item, window).select(:id))
            .where.not(start_time: nil).where.not(end_time: nil)
          last = upcoming ? window.ends_on&.in_time_zone&.end_of_day : window.end_time
          scope = scope.where(start_time: ..last) if last
          scope = scope.where(start_time: window.start_time..) if window.start_time
          scope
        end

        private

        def cast_rule(row)
          share = row["share"].to_s.strip
          {
            "name" => row["name"].to_s.strip.presence,
            "starts" => row["starts"].respond_to?(:to_h) ? RelativeDate.cast(row["starts"]) : nil,
            "ends_on" => cast_date(row["ends_on"]),
            "share" => share.match?(/\A\d+\z/) ? share.to_i : share.presence,
            "weekly" => ActiveModel::Type::Boolean.new.cast(row["weekly"]) || false,
            "with" => row["with"].to_s.strip.presence,
            "judge_after" => row["judge_after"].to_i
          }
        end

        def cast_date(value)
          value = value.to_s.strip
          return if value.blank?

          Date.parse(value).iso8601
        rescue Date::Error
          value
        end

        def rule_filled?(rule)
          %w[name starts ends_on share with].any? { |field| rule[field].present? } || rule["weekly"] || rule["judge_after"].positive?
        end

        def whole_number(value)
          value.is_a?(Integer) ? value : Integer(value.to_s, 10)
        rescue ArgumentError
          nil
        end

        def validate_periods(item)
          ids = period_ids(item)
          return if ids.empty? || item.checklist.nil?

          outside = TimeClockPeriod.where(id: ids).where.not(id: team_periods(item.checklist).select(:id))
          item.errors.add(:base, "Pick time clock periods of this checklist's team or the teams below it") if outside.exists?
        end

        # Rules linked by "counted together with", in either direction and
        # through others, share one pool.
        def assign_pools(rules)
          by_name = rules.index_by(&:name)
          rules.each do |rule|
            next if rule.pool

            members = []
            queue = [ rule ]
            while (current = queue.shift)
              next if members.include?(current)

              members << current
              linked = rules.select { |other| other.with == current.name }
              linked << by_name[current.with] if current.with
              queue.concat(linked.compact)
            end
            members = rules & members
            pool = Pool.new(key: members.map(&:name).join("\u0000"), label: members.map(&:name).join(" and "), rules: members)
            members.each { |member| member.pool = pool }
          end
        end

        def rule_sentence(rule)
          share = "#{rule.share}% of meeting hours"
          share += " each week" if rule.weekly
          share += " #{rule.starts.describe}" if rule.starts&.relative?
          others = rule.pool.rules.map(&:name) - [ rule.name ]
          others.any? ? "#{share} in #{rule.name}, counted together with #{others.to_sentence}" : "#{share} in #{rule.name}, judged on its own"
        end

        def parse_date(value)
          value.present? ? Date.iso8601(value.to_s) : nil
        rescue Date::Error
          nil
        end
      end

      def evaluate(person_ids)
        rules = self.class.rules(item, as_of: context.as_of)
        meetings = self.meetings
        excused = excused_meeting_ids(person_ids)
        punches = punches_by_person(person_ids)
        shared = Tally.new(meetings, rules, window)
        options = { extra_hours_count: config["extra_hours_count"] == true, leeway: leeway_seconds }

        person_ids.index_with do |person_id|
          excuses = excused.fetch(person_id, []).index_by(&:event_id)
          mine = punches.fetch(person_id, [])
          next result_for(shared.person(mine, **options), []) if excuses.empty?

          kept, skipped = meetings.partition { |meeting| excuses.exclude?(meeting.id) }
          tally = Tally.new(kept, rules, window)
          # Time at an excused meeting is neither credit nor extra time.
          cut = Tally.subtract(Tally.merge(skipped.map { |meeting| [ meeting.start_time, meeting.end_time ] }), tally.meeting_intervals)
          result_for(tally.person(Tally.subtract(Tally.merge(mine), cut), **options), skipped.map { |meeting| [ meeting, excuses[meeting.id] ] })
        end
      end

      # Meetings held by the as-of moment, in order.
      def meetings
        @meetings ||= self.class.meetings_scope(item, window).where("events.end_time < ?", context.as_of).order(:start_time).to_a
      end

      # { event_id => seconds } a person was punched in at each meeting.
      def time_at_meetings(person_id)
        mine = Tally.merge(punches_by_person([ person_id ]).fetch(person_id, []))
        meetings.to_h { |meeting| [ meeting.id, Tally.overlap(mine, [ [ meeting.start_time, meeting.end_time ] ]) ] }
      end

      private

      def leeway_seconds
        (config["leeway_minutes"].nil? ? 1 : config["leeway_minutes"].to_i) * 60
      end

      # [start, end] punches per person on the meetings' periods, cut to the
      # window (which ends at the as-of moment at the latest).
      def punches_by_person(person_ids)
        from = window.start_time
        to = window.end_time
        punches = ::TimeClockPunch.where(person_id: person_ids, time_clock_period_id: self.class.periods(item, window).select(:id))
          .where.not(end_time: nil).where(start_time: ...to)
        punches = punches.where(end_time: from..) if from
        punches.pluck(:person_id, :start_time, :end_time).group_by(&:first).transform_values do |rows|
          rows.map { |_, start_time, end_time| [ from ? [ start_time, from ].max : start_time, [ end_time, to ].min ] }
            .select { |start_time, end_time| end_time > start_time }
        end
      end

      # { person_id => [ChecklistExcuse] } for meetings they're excused from.
      def excused_meeting_ids(person_ids)
        return {} unless item.persisted?

        ChecklistExcuse.where(item_id: item.id, person_id: person_ids).where.not(event_id: nil)
          .in_force(context.as_of.to_date).includes(:created_by).group_by(&:person_id)
      end

      def result_for(person, excused)
        measures = { "meetings" => person.attended, "held" => person.held_meetings, "credited" => person.credited_hours,
          "percent" => person.percent&.round(1), "extra" => person.extra_hours }
        lines = person.checks.map { |check| check_line(check) }
        lines.concat(excused.map { |meeting, excuse| "Excused from #{meeting_name(meeting)} by #{excuse.created_by&.display_name || "a manager"}, #{short_date(excuse.created_at)}" })
        detail = lines.join("; ")

        if person.checks.empty?
          return Result.exempt("No meetings yet", detail: excused.any? ? detail : "No meetings held yet", measures: measures)
        end

        summary = "#{format_percent(person.percent)} of #{format_hours(person.held_hours)} h"
        if person.checks.any? { |check| check.judged? && !check.pass? }
          Result.not_met(summary, label: "Below minimum", detail: detail, measures: measures)
        elsif (waiting = person.checks.find { |check| !check.judged? })
          Result.pending("Counted after #{waiting.judge_after} meetings; #{waiting.counted} held", detail: detail, measures: measures)
        else
          Result.met(summary, detail: detail, measures: measures)
        end
      end

      def check_line(check)
        unless check.judged?
          return "… #{check.label}: counted after #{check.judge_after} meetings; #{check.counted} held"
        end

        mark = check.pass? ? "✓" : "✗"
        held = format_hours(Tally.hours(check.held))
        if check.share
          got = check.held.positive? ? check.got / check.held * 100 : 0
          "#{mark} #{check.label}: #{format_percent(got)} of #{held} h (needs #{check.share.to_s.sub(/\.0\z/, "")}%)"
        else
          "#{mark} #{check.label}: #{format_hours(Tally.hours(check.got))} h of #{held} h (needs #{format_hours(Tally.hours(check.needed))} h)"
        end
      end

      def meeting_name(meeting)
        "#{meeting.name.presence || "the meeting"} (#{short_date(meeting.start_time)})"
      end

      def short_date(time)
        time.in_time_zone.strftime("%b %-d")
      end

      def format_hours(value)
        value.to_f.round(2).to_s.sub(/\.0\z/, "")
      end

      def format_percent(value)
        value.nil? ? "—" : "#{value.round(1).to_s.sub(/\.0\z/, "")}%"
      end
    end
  end
end
