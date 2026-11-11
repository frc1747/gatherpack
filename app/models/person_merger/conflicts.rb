class PersonMerger
  # on_conflict and check callables for the built-in registrations.
  module Conflicts
    module_function

    # A duplicate check-in at the same event: keep the kept check-in, but
    # carry over the removed one's notes and the answers it has that the kept
    # one lacks, so nothing recorded at either check-in is lost.
    def checkins(removed, kept)
      checkin = Checkin.find(kept["id"])
      if removed["notes"].present?
        checkin.update_columns(notes: [ checkin.notes.presence, removed["notes"] ].compact.uniq.join("; "))
      end

      answered = checkin.checkin_field_responses.where.not(response: [ nil, "" ]).pluck(:checkin_field_id)
      CheckinFieldResponse.where(checkin_id: removed["id"]).where.not(response: [ nil, "" ])
        .where.not(checkin_field_id: answered).find_each do |response|
        checkin.checkin_field_responses.where(checkin_field_id: response.checkin_field_id).delete_all
        response.update_columns(checkin_id: checkin.id)
      end
    end

    # Punches move as they are, but ones that overlap the kept person's
    # (including both being clocked in) would count hours twice.
    def time_clock_punches(from, to)
      overlapping = ActiveRecord::Base.connection.select_value(ActiveRecord::Base.sanitize_sql_array([ <<~SQL, from, to ])).to_i
        SELECT COUNT(DISTINCT p1.id) FROM time_clock_punches p1
        JOIN time_clock_punches p2
          ON p1.start_time < COALESCE(p2.end_time, 'infinity'::timestamptz)
          AND p2.start_time < COALESCE(p1.end_time, 'infinity'::timestamptz)
        WHERE p1.person_id = ? AND p2.person_id = ?
      SQL
      return if overlapping.zero?

      both_in = TimeClockPunch.still_clocked_in.where(person_id: from).exists? &&
        TimeClockPunch.still_clocked_in.where(person_id: to).exists?
      [
        "#{overlapping} #{"punch".pluralize(overlapping)} overlap the kept person's, so hours may count twice.",
        ("Both are clocked in now." if both_in),
        "Check the punches after the merge."
      ].compact.join(" ")
    end
  end
end
