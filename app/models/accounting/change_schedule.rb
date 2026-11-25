# How often a source with a change feed is checked for changes, and
# whether it's due. A source stores one word (CHOICES keys) in its
# "change_check" setting; the labels are for screens only. Times are in the
# site's time zone.
#
# A check is due when the latest scheduled time that has passed (the
# start of this hour, or 6:00 or 18:00 today or yesterday) is later than
# the last check, so a missed run is made up at the next tick instead of
# waiting for the next window.
class Accounting::ChangeSchedule
  DEFAULT = "15m".freeze

  # word => [ label on the form, words after "Checks QuickBooks" ]
  CHOICES = {
    "15m" => [ "Every 15 minutes", "every 15 minutes" ],
    "hourly" => [ "Every hour", "every hour" ],
    "twice_daily" => [ "Twice a day (6 am and 6 pm)", "twice a day (6 am and 6 pm)" ],
    "daily" => [ "Once a day (6 am)", "once a day (6 am)" ],
    "manual" => [ "Only when someone clicks Sync now", "only when someone clicks Sync now" ]
  }.freeze
  DAILY_HOURS = { "twice_daily" => [ 6, 18 ], "daily" => [ 6 ] }.freeze

  def self.choices = CHOICES.map { |word, (label, _)| [ label, word ] }
  def self.words = CHOICES.keys

  # The source's stored word, or the default when it has none or an unknown one.
  def self.word_for(source)
    stored = source.try(:change_check).presence
    CHOICES.key?(stored) ? stored : DEFAULT
  end

  attr_reader :source

  def initialize(source)
    @source = source
  end

  def word
    self.class.word_for(source)
  end

  def manual?
    word == "manual"
  end

  # "every hour", "only when someone clicks Sync now"
  def description
    CHOICES.fetch(word, CHOICES.fetch(DEFAULT)).last
  end

  # "Checks QuickBooks twice a day (6 am and 6 pm)."
  def sentence
    "Checks #{source.source_name} #{description}."
  end

  # Whether the scheduler should queue a check now. A source that has never
  # been checked is due, except one that's only checked on request.
  def due?(now = Time.current)
    return false if manual?

    started = last_checked
    return true if started.nil? || word == "15m"

    started < latest_boundary(now)
  end

  # When the last check of changes began, or nil. The sync stores it a
  # minute early so the next check overlaps it.
  def last_checked
    checked = source.last_change_check_time
    checked + Accounting::Sync::OVERLAP if checked
  end

  private
    def latest_boundary(now)
      zone = Time.find_zone(Settings[:time_zone].presence || "UTC") || Time.find_zone!("UTC")
      local = now.in_time_zone(zone)
      case word
      when "hourly" then local.beginning_of_hour
      else
        hours = DAILY_HOURS.fetch(word)
        [ local.to_date, local.to_date - 1 ].product(hours).map { |day, hour| zone.local(day.year, day.month, day.day, hour) }
          .select { |time| time <= local }.max
      end
    end
end
