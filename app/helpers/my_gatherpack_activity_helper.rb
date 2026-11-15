# Words and links for the activity page and Home's "Also this season".
module MyGatherpackActivityHelper
  # "6 h", "3.5 h", or "—" when nothing had set times.
  def activity_hours(hours)
    return "—" if hours.nil?

    "#{number_with_precision(hours, precision: 1, strip_insignificant_zeros: true)} h"
  end

  # "Outreach: 2 events · 6 h"
  def activity_uncounted_line(row)
    [ "#{row.name}: #{pluralize(row.events, "event")}", (activity_hours(row.hours) if row.hours) ].compact.join(" · ")
  end

  # "2 events · 6 h"; meetings without meeting events held say only their hours.
  def activity_kind_detail(row)
    count = pluralize(row.events, row.meetings? ? "meeting" : "event") unless row.meetings? && row.events.zero?
    [ count, activity_hours(row.hours) ].compact.join(" · ")
  end

  # "Counts toward ..." with the covering items the viewer may see that
  # count the row; nil when it shows none (a row counted only by items
  # hidden from the viewer says nothing). A checklist that doesn't cover
  # the person is never named.
  def activity_counts_toward(activity, row)
    labels = activity.counts_toward(row)
    "Counts toward #{labels.to_sentence}" if labels.any?
  end

  # How much of a row no item covering the person counts, from
  # Activity#uncounted as Home's "Also this season"; nil when all of it
  # counts, and always for meetings.
  def activity_not_required(activity, row)
    rest = row.uncounted
    return if rest.nil?

    whom = activity.own? ? "you" : "them"
    rest.events == row.events ? "Not required for #{whom}" : "#{pluralize(rest.events, "event")} not required for #{whom}"
  end

  # The page for this person, keeping the viewer's own page free of a person id.
  def activity_page_path(person, **params)
    params[:person] = person.neat_id unless person.id == current_user.person&.id
    activity_path(params.compact_blank)
  end

  def activity_entry_path(entry)
    case entry.record
    when Event then event_path(entry.record)
    when SignupSheet then signup_sheet_path(entry.record)
    when FormResponse then form_response_path(entry.record.form, entry.record.subject)
    end
  end

  # "Mon Oct 5 · 2 h"
  def activity_entry_when(entry)
    [ entry.at.strftime("%a %b %-d"), (activity_hours(entry.hours) if entry.hours) ].compact.join(" · ")
  end

  # The person's own upcoming sign-ups (Activity#upcoming_signups) as rows.
  def activity_signup_items(activity)
    activity.upcoming_signups.map { |signup| family_signup_item(signup) }
  end

  # The checklist's own page for the viewer, the person's checklists tab for a ward.
  def activity_checklist_path(activity, checklist)
    activity.own? ? checklist_path(checklist) : person_checklists_path(activity.person)
  end

  def activity_first_name(person)
    person.first_name.presence || person.identifier_name
  end
end
