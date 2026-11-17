module MyGatherpack
  # One year of activity, from the month and day in
  # Settings[:my_gatherpack_season_start] ("MM-DD", May 1 when blank or
  # unreadable). A record on the start date belongs to the season it starts.
  class Season
    include Comparable

    DEFAULT_START = [ 5, 1 ].freeze

    class << self
      def current(today = Time.zone.today)
        containing(today)
      end

      def containing(date)
        date = date.to_date
        starts = start_in(date.year)
        new(date < starts ? start_in(date.year - 1) : starts)
      end

      # The season that starts in this year.
      def starting_in(year)
        new(start_in(year))
      end

      # [month, day] from the setting.
      def start_month_day
        month, day = Settings[:my_gatherpack_season_start].to_s.strip.split("-", 2).map { |part| Integer(part, 10) }
        Date.valid_date?(2024, month, day) ? [ month, day ] : DEFAULT_START
      rescue ArgumentError, TypeError
        DEFAULT_START
      end

      private

      # February 29 starts on March 1 in other years.
      def start_in(year)
        month, day = start_month_day
        Date.valid_date?(year, month, day) ? Date.new(year, month, day) : Date.new(year, month, day - 1) + 1
      end
    end

    attr_reader :starts_on

    def initialize(starts_on)
      @starts_on = starts_on.to_date
    end

    def <=>(other)
      starts_on <=> other.starts_on if other.is_a?(Season)
    end

    def eql?(other)
      self == other
    end

    def hash
      starts_on.hash
    end

    def ends_on
      next_season.starts_on - 1
    end

    def next_season
      self.class.starting_in(starts_on.year + 1)
    end

    # From the start of the first day to the start of the next season's.
    def times
      starts_on.in_time_zone.beginning_of_day...next_season.starts_on.in_time_zone.beginning_of_day
    end

    def cover?(time)
      times.cover?(time)
    end

    def year
      starts_on.year
    end

    # "2026–27", or "2026" for a season that starts on January 1.
    def label
      ends_on.year == year ? year.to_s : "#{year}–#{ends_on.strftime("%y")}"
    end

    def to_param
      year.to_s
    end

    def current?
      self == self.class.current
    end
  end
end
