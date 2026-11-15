# Words and links for the activity page and Home's "Also this season".
module MyGatherpackActivityHelper
  SIGNUP_LIMIT = 20

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

  # The covering items that count it, or "Not required for you" for the rows
  # Activity#uncounted gives Home's "Also this season" too. A checklist that
  # doesn't cover the person is never named. Meetings no item counts say nothing.
  def activity_counts_toward(activity, row)
    if row.counted? then "Counts toward #{row.counts_toward.to_sentence}"
    elsif activity.uncounted.include?(row) then "Not required for you"
    end
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

  # Upcoming sign-ups that are the person's own (taken by them or on their
  # behalf), as the family page and Home find them.
  def activity_signup_items(activity)
    return [] unless GatherPack::Features.enabled?(:signups)

    person = activity.person
    signups = if activity.own?
      SignupsSummary.new(current_user, limit: SIGNUP_LIMIT).signups.select { |signup| [ signup.person_id, signup.on_behalf_of_id ].include?(person.id) }
    else
      family_signups([ person ]).fetch(person.id, []).first(SIGNUP_LIMIT)
    end
    signups.map { |signup| family_signup_item(signup) }
  end

  # The checklist's own page for the viewer, the person's checklists tab for a ward.
  def activity_checklist_path(activity, checklist)
    activity.own? ? checklist_path(checklist) : person_checklists_path(activity.person)
  end

  def activity_first_name(person)
    person.first_name.presence || person.identifier_name
  end
end
