module Checklists
  module Kinds
    # Attendance at meetings (spec §6.3). Meetings are events linked to a
    # time clock period that start within the item's dates and have ended;
    # every period overlapping the dates is used unless the item names one.
    # Credit is punched time overlapping a meeting, merged, so leaving early
    # costs and staying late adds nothing. With extra hours counting, time
    # punched outside meetings makes up missed time in the same group, never
    # above 100%.
    #
    # Rules are rows in the config (rule_1_name, rule_1_starts_on, ...), so
    # the item form, preview and copy work on them like any other setting.
    # A rule is a share of meeting hours over dates, optionally for every
    # week on its own, judged alone or counted together with other rules (a
    # pool), and judged only once enough meetings are held. Each meeting's
    # hours count toward a pool's minimum at its own rule's share. Nothing is
    # built in: no months, shares or pools.
    #
    # A manager can excuse a person from one meeting (a ChecklistExcuse with
    # an event): it leaves their required and credited hours.
    class Attendance < ItemKind
      RULES = 4

      # A rule row from the config, with the pool it's judged in.
      Rule = Struct.new(:name, :starts_on, :ends_on, :share, :weekly, :with, :judge_after, :pool, keyword_init: true) do
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
          periods = [ [ "Any period", "" ] ] + TimeClockPeriod.order(start_time: :desc).pluck(:name, :id)
          [
            ItemKind::Setting.new(key: :period_id, type: :choice, label: "Time clock period", options: periods,
              hint: "Any period: every period overlapping the item's dates"),
            ItemKind::Setting.new(key: :extra_hours_count, type: :boolean,
              label: "Time outside meetings makes up missed meeting time",
              hint: "Within the same rule, or the same week for weekly rules. Never above 100%"),
            ItemKind::Setting.new(key: :leeway_minutes, type: :number, label: "Leeway (minutes)",
              hint: "Someone this close to a minimum passes. Blank: 1")
          ] + (1..RULES).flat_map { |number| rule_settings(number) }
        end

        def references = { "period_id" => "TimeClockPeriod" }

        def invalidations
          [
            [ ::TimeClockPunch, ->(punch) { [ punch.person_id ] } ],
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

        # The item's rule rows, in order, each with its pool. Rows with no
        # name and no share are empty slots.
        def rules(item)
          config = item.config || {}
          rules = (1..RULES).filter_map do |number|
            values = %w[name starts_on ends_on share weekly with judge_after].to_h { |field| [ field, config["rule_#{number}_#{field}"] ] }
            next if values["name"].blank? && values["share"].blank?

            Rule.new(name: values["name"].presence || "Rule #{number}", starts_on: parse_date(values["starts_on"]),
              ends_on: parse_date(values["ends_on"]), share: values["share"].to_f, weekly: values["weekly"] == true,
              with: values["with"].to_s.strip.presence, judge_after: values["judge_after"].to_i)
          end
          assign_pools(rules)
          rules
        end

        def validate(item)
          rules = rules(item)
          return item.errors.add(:base, "Add at least one rule with a share of meeting hours") if rules.empty?

          names = rules.map(&:name)
          names.tally.each { |name, count| item.errors.add(:base, "Two rules are named #{name}") if count > 1 }
          rules.each do |rule|
            item.errors.add(:base, "#{rule.name}: the share must be from 0 to 100%") unless (0..100).cover?(rule.share)
            item.errors.add(:base, "#{rule.name} ends before it starts") if rule.starts_on && rule.ends_on && rule.ends_on < rule.starts_on
            item.errors.add(:base, "#{rule.name} is counted together with #{rule.with}, but no other rule has that name") if rule.with && (rule.with == rule.name || names.exclude?(rule.with))
          end
          rules.map(&:pool).uniq.each do |pool|
            item.errors.add(:base, "Rules counted together must all be weekly, or none of them") if pool.rules.map(&:weekly).uniq.size > 1
          end
          item.errors.add(:base, "The leeway can't be negative") if item.config["leeway_minutes"].to_i.negative?
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
        # one's end (just after, so it counts as held).
        def next_change_at(item, context)
          window = context.window_for(item)
          ends = meetings_scope(item, window, upcoming: true).where("events.end_time >= ?", context.as_of).minimum(:end_time)
          ends && ends + 1.second
        end

        def describe(item)
          rules = rules(item)
          return item.label if rules.empty?

          "At least " + rules.map { |rule| rule_sentence(rule) }.join("; ")
        end

        # Periods overlapping the window, or the one the item names.
        def periods(item, window)
          return TimeClockPeriod.where(id: item.config["period_id"]) if item.config["period_id"].present?

          periods = TimeClockPeriod.all
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

        def rule_settings(number)
          prefix = "rule_#{number}"
          [
            ItemKind::Setting.new(key: :"#{prefix}_name", type: :text, label: "Rule #{number}: name",
              hint: number == 1 ? "e.g. \"Fall\". Leave a rule's name and share blank to skip it" : nil),
            ItemKind::Setting.new(key: :"#{prefix}_starts_on", type: :date, label: "Rule #{number}: from", hint: "Blank: the item's start"),
            ItemKind::Setting.new(key: :"#{prefix}_ends_on", type: :date, label: "Rule #{number}: until", hint: "Blank: the item's end"),
            ItemKind::Setting.new(key: :"#{prefix}_share", type: :number, label: "Rule #{number}: share of meeting hours (%)"),
            ItemKind::Setting.new(key: :"#{prefix}_weekly", type: :boolean, label: "Rule #{number}: every week passes on its own"),
            ItemKind::Setting.new(key: :"#{prefix}_with", type: :text, label: "Rule #{number}: counted together with",
              hint: "Another rule's name, to judge their meetings as one. Blank: judged on its own"),
            ItemKind::Setting.new(key: :"#{prefix}_judge_after", type: :number, label: "Rule #{number}: judge after this many meetings",
              hint: "Until then it shows as Almost. Blank or 0: from the first meeting")
          ]
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
          share = "#{rule.share.to_s.sub(/\.0\z/, "")}% of meeting hours"
          share += " each week" if rule.weekly
          others = rule.pool.rules.map(&:name) - [ rule.name ]
          others.any? ? "#{share} in #{rule.name}, counted together with #{others.to_sentence}" : "#{share} in #{rule.name}"
        end

        def parse_date(value)
          value.present? ? Date.iso8601(value.to_s) : nil
        rescue Date::Error
          nil
        end
      end

      def evaluate(person_ids)
        rules = self.class.rules(item)
        meetings = self.meetings
        excused = excused_meeting_ids(person_ids)
        punches = punches_by_person(person_ids)
        shared = Tally.new(meetings, rules, window)
        options = { extra_hours_count: config["extra_hours_count"] == true, leeway: leeway_seconds }

        person_ids.index_with do |person_id|
          skipped = excused.fetch(person_id, [])
          tally = skipped.empty? ? shared : Tally.new(meetings.reject { |meeting| skipped.include?(meeting.id) }, rules, window)
          result_for(tally.person(punches.fetch(person_id, []), **options), meetings.select { |meeting| skipped.include?(meeting.id) })
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

      # Merged [start, end] punches per person, cut off at the as-of moment.
      # Punches on the meetings' periods count, and punches on no period.
      def punches_by_person(person_ids)
        periods = self.class.periods(item, window).select(:id)
        punches = ::TimeClockPunch.where(person_id: person_ids).where.not(end_time: nil).where(start_time: ...context.as_of)
        punches = punches.where(end_time: window.start_time..) if window.start_time
        punches = punches.where(time_clock_period_id: periods).or(punches.where(time_clock_period_id: nil))
        punches.pluck(:person_id, :start_time, :end_time).group_by(&:first).transform_values do |rows|
          rows.map { |_, start_time, end_time| [ start_time, [ end_time, context.as_of ].min ] }
        end
      end

      # { person_id => [event_id] } for meetings they're excused from.
      def excused_meeting_ids(person_ids)
        return {} unless item.persisted?

        ChecklistExcuse.where(item_id: item.id, person_id: person_ids).where.not(event_id: nil)
          .in_force(context.as_of.to_date).pluck(:person_id, :event_id)
          .group_by(&:first).transform_values { |rows| rows.map(&:last) }
      end

      def result_for(person, excused)
        measures = { "meetings" => person.attended, "held" => person.held_meetings, "credited" => person.credited_hours,
          "percent" => person.percent&.round(1), "extra" => person.extra_hours }
        lines = person.checks.map { |check| check_line(check) }
        lines << "Excused from #{excused.map { |meeting| meeting_name(meeting) }.to_sentence}" if excused.any?
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
        "#{meeting.name.presence || "the meeting"} (#{meeting.start_time.in_time_zone.strftime("%b %-d")})"
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
