module MyGatherpackHoursHelper
  HoursTotal = Struct.new(:label, :hours, keyword_init: true)

  # Hours for the phone's My Hours total: one person, in the selected Time Clock
  # Period or else the periods running today. Nil when the list covers several
  # people or no period applies. Punches with no period aren't counted.
  def my_gatherpack_hours_total(search)
    periods = my_gatherpack_hours_periods
    return if periods.empty?

    punches = search.result.reorder(nil)
    person_ids = punches.distinct.limit(2).pluck(:person_id)
    return unless person_ids.one?

    hours = punches.where(person_id: person_ids.first, time_clock_period_id: periods.map(&:id))
                   .where.not(end_time: nil)
                   .sum(Arel.sql("ROUND(EXTRACT(EPOCH FROM (time_clock_punches.end_time - time_clock_punches.start_time)) / 3600 * 20) / 20.0"))
    HoursTotal.new(label: "Hours in #{periods.map(&:name).to_sentence}", hours: hours)
  end

  # "Mon Mar 2, 9:00AM – 11:30AM"; the end shows its date when it isn't the start's
  # day, and a date shows its year when it isn't this year's.
  def my_gatherpack_punch_times(punch)
    start_time = punch.start_time
    finish = punch.end_time
    text = my_gatherpack_punch_moment(start_time, date: true)
    return "#{text} – Still Clocked In" if finish.nil?

    "#{text} – #{my_gatherpack_punch_moment(finish, date: finish.to_date != start_time.to_date)}"
  end

  private

  def my_gatherpack_hours_periods
    periods = policy_scope(TimeClockPeriod)
    selected = params.dig(:q, :time_clock_period_id_eq).presence
    return periods.where(id: selected).to_a if selected

    now = Time.current
    periods.where("start_time <= ? AND end_time >= ?", now, now).to_a
  end

  def my_gatherpack_punch_moment(time, date:)
    format = date ? (time.year == Time.current.year ? "%a %b %-d, %-I:%M%p" : "%a %b %-d %Y, %-I:%M%p") : "%-I:%M%p"
    time.strftime(format)
  end
end
