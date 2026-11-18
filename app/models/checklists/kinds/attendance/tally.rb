module Checklists
  module Kinds
    class Attendance < ItemKind
      # The arithmetic of the attendance item, for one set of meetings:
      # merged meeting time, the groups each rule is judged in (a pool, or
      # one week of a weekly rule) and what each group needs. person(punches)
      # applies it to one person's punches.
      #
      # Times are merged [start, end] intervals so nothing counts twice.
      # Hours are rounded to the nearest 0.05.
      class Tally
        # One group's verdict for one person. share is set when the group is
        # a single rule, so the line can read as a percentage.
        Check = Struct.new(:label, :got, :held, :needed, :share, :judge_after, :counted, :pass, keyword_init: true) do
          def pass? = pass
          def judged? = counted >= judge_after
        end

        # One person's numbers.
        Person = Struct.new(:attended, :held_meetings, :credited_hours, :held_hours, :percent, :extra_hours, :checks, keyword_init: true)

        Group = Struct.new(:key, :label, :intervals, :held, :needed, :share, :pool, keyword_init: true)

        def self.merge(intervals)
          intervals.sort.each_with_object([]) do |(start_time, end_time), merged|
            if merged.any? && start_time <= merged.last[1]
              merged.last[1] = [ merged.last[1], end_time ].max
            else
              merged << [ start_time, end_time ]
            end
          end
        end

        def self.overlap(a, b)
          a.sum { |a_start, a_end| b.sum { |b_start, b_end| [ [ a_end, b_end ].min - [ a_start, b_start ].max, 0 ].max } }
        end

        # The parts of merged intervals outside the merged cuts.
        def self.subtract(intervals, cuts)
          intervals.flat_map do |start_time, end_time|
            pieces = [ [ start_time, end_time ] ]
            cuts.each do |cut_start, cut_end|
              pieces = pieces.flat_map do |piece_start, piece_end|
                next [ [ piece_start, piece_end ] ] if cut_end <= piece_start || cut_start >= piece_end

                [ [ piece_start, cut_start ], [ cut_end, piece_end ] ].select { |from, to| to > from }
              end
            end
            pieces
          end
        end

        def self.duration(intervals)
          intervals.sum { |start_time, end_time| end_time - start_time }
        end

        def self.hours(seconds)
          (seconds / 3600.0 * 20).round / 20.0
        end

        attr_reader :meetings, :rules, :window

        def initialize(meetings, rules, window)
          @meetings = meetings
          @rules = rules
          @window = window
        end

        def meeting_intervals
          @meeting_intervals ||= Tally.merge(meetings.map { |meeting| [ meeting.start_time, meeting.end_time ] })
        end

        def rule_for(time)
          date = time.in_time_zone.to_date
          rules.find { |rule| rule.cover?(date, window) }
        end

        # A pool's meetings, or one week of a weekly rule's.
        def group_key(time)
          rule = rule_for(time)
          return unless rule

          [ rule.pool.key, rule.weekly ? time.in_time_zone.to_date.beginning_of_week : nil ]
        end

        def groups
          @groups ||= meetings.group_by { |meeting| group_key(meeting.start_time) }.reject { |key, _| key.nil? }.map do |(pool_key, week), events|
            pool = rule_for(events.first.start_time).pool
            intervals = Tally.merge(events.map { |event| [ event.start_time, event.end_time ] })
            needed = events.group_by { |event| rule_for(event.start_time) }.sum do |rule, rule_events|
              Tally.duration(Tally.merge(rule_events.map { |event| [ event.start_time, event.end_time ] })) * rule.share.to_i / 100.0
            end
            Group.new(key: [ pool_key, week ], label: week ? "#{pool.label}, week of #{week.strftime("%b %-d")}" : pool.label,
              intervals: intervals, held: Tally.duration(intervals), needed: needed, pool: pool,
              share: (pool.rules.first.share if pool.rules.size == 1))
          end
        end

        # Meetings held under each pool's rules, over all its weeks, for
        # "judge after N meetings".
        def counted_by_pool
          @counted_by_pool ||= meetings.filter_map { |meeting| rule_for(meeting.start_time)&.pool&.key }.tally
        end

        def person(punches, extra_hours_count: false, leeway: 60)
          mine = Tally.merge(punches)
          credited = Tally.overlap(mine, meeting_intervals)
          # Time outside meetings, in the group its punch started in.
          extra_by_group = Hash.new(0)
          mine.each do |start_time, end_time|
            key = group_key(start_time)
            extra_by_group[key] += (end_time - start_time) - Tally.overlap([ [ start_time, end_time ] ], meeting_intervals) if key
          end

          checks = groups.map do |group|
            got = Tally.overlap(mine, group.intervals)
            got += [ extra_by_group[group.key], group.held - got ].min if extra_hours_count
            Check.new(label: group.label, got: got, held: group.held, needed: group.needed, share: group.share,
              judge_after: group.pool.judge_after, counted: counted_by_pool.fetch(group.pool.key, 0), pass: got + leeway >= group.needed)
          end

          held_hours = Tally.hours(Tally.duration(meeting_intervals))
          Person.new(
            attended: meetings.count { |meeting| Tally.overlap(mine, [ [ meeting.start_time, meeting.end_time ] ]) > 0 },
            held_meetings: meetings.size,
            credited_hours: Tally.hours(credited),
            held_hours: held_hours,
            percent: held_hours > 0 ? Tally.hours(credited) / held_hours * 100 : nil,
            extra_hours: [ Tally.hours(Tally.duration(mine) - credited), 0 ].max,
            checks: checks
          )
        end
      end
    end
  end
end
