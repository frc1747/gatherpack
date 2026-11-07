# Housekeeping's feature switch, the built-in types, purges and activity
# sources, and the patches it makes to other list pages. Uses
# config.to_prepare (like checklists.rb) because the registries live in
# reloadable app/ code.
#
# Another branch registers its own model the same way:
#
#   Rails.application.config.to_prepare do
#     next unless defined?(Housekeeping) && Housekeeping.respond_to?(:register)
#
#     Housekeeping.register(Form, ended_on: ->(form) { form.closes_at }, ...)
#   end
Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :housekeeping,
      label: "Housekeeping",
      description: "Archive, restore and copy forward old records, and clear old personal data, by date from their list pages",
      default_enabled: false
    )
  )

  Settings.register(:housekeeping_purge_fields, :text, "Medical and Emergency Fields", "", "Housekeeping",
    "Person fields whose answers count as medical or emergency details, one field name or field group name per line. " \
    "Admins can clear these answers for people with no activity for a while")

  # Checklists archive themselves each night under their own setting
  # (checklists_archive_after), so they don't get a second one here.
  Housekeeping.register(Checklist,
    ended_on: :ends_on,
    available: -> { Checklists.enabled? },
    archived: ->(scope) { scope.archived },
    archive: ->(checklist) { checklist.update!(status: :archived) },
    restore: ->(checklist) { checklist.update!(status: :active) },
    used_by: ->(checklist) { checklist.dependents.refreshable.pluck(:title) },
    permitted: ->(user, checklist, _action) { checklist.organizer?(user.person) },
    copy: Checklists::Copier,
    auto_archive: false,
    list_path: :checklists_path)
  Housekeeping.register(Event, ended_on: :end_time, available: -> { GatherPack::Features.enabled?(:events) }, list_path: :events_path)
  Housekeeping.register(Announcement, ended_on: :end_time, list_path: :announcements_path)

  Housekeeping.register_purge(:denied_applications,
    label: "Denied applications",
    page: :membership_applications,
    default_months: 12,
    description: "Membership applications denied",
    records: ->(cutoff) { MembershipApplication.denied.where("COALESCE(reviewed_at, updated_at) < ?", cutoff.in_time_zone) },
    describe: ->(records) {
      records.includes(:person, :team).map do |application|
        [ application.person.display_name, "#{application.team.name}, denied #{I18n.l((application.reviewed_at || application.updated_at).to_date, format: :long)}" ]
      end
    })
  Housekeeping.register_purge(:field_answers,
    label: "Medical and emergency answers",
    page: :people,
    default_months: 36,
    description: "Answers to the medical and emergency fields of people with no activity",
    available: -> { GatherPack::Features.enabled?(:person_fields) },
    records: ->(cutoff) { Housekeeping::FieldAnswers.records(cutoff) },
    describe: ->(records) { Housekeeping::FieldAnswers.describe(records) })

  # What counts as activity for "no activity since". Forms and sign-up
  # sheets add theirs.
  Housekeeping.register_activity(:time_clock_punches) { |since| TimeClockPunch.where(start_time: since..).select(:person_id) }
  Housekeeping.register_activity(:checkins) { |since| Checkin.where(created_at: since..).select(:person_id) }

  Housekeeping::ListFilters.hide_archived(EventsController, :@events, :events)
  Housekeeping::ListFilters.hide_archived(AnnouncementsController, :@announcements, :announcements)
  Housekeeping::ListFilters.no_activity(PeopleController, :@people)
  Announcement.singleton_class.prepend(Housekeeping::ListFilters::VisibleUnarchived)
end
