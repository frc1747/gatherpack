# Date housekeeping: anything old can be found, archived, restored, copied
# forward or purged by date, the same way for every kind of record.
#
# A feature registers its model from an initializer; nothing here names one:
#
#   Housekeeping.register(Event, ended_on: :end_time)
#   Housekeeping.register(Checklist, ended_on: :ends_on,
#     archived: ->(scope) { scope.archived },
#     archive: ->(checklist) { checklist.update!(status: :archived) },
#     restore: ->(checklist) { checklist.update!(status: :active) },
#     used_by: ->(checklist) { checklist.dependents.refreshable.pluck(:title) })
#
# Retention purges and the sources of a person's activity register the same
# way (register_purge, register_activity). See Housekeeping::Type for the
# options and HousekeepingNightlyJob for automatic archiving.
module Housekeeping
  class << self
    def enabled?
      GatherPack::Features.enabled?(:housekeeping)
    end

    # model: an ActiveRecord class. key: the URL name (default the table name).
    # The rest are Housekeeping::Type's options.
    def register(model, key: nil, **options)
      type = Type.new(model, key: key, **options)
      types[type.key] = type
      register_setting(type) if type.auto_archive?
      type
    end

    def types
      @types ||= {}
    end

    # The registered type for a key, when its feature is on.
    def type(key)
      found = types[key.to_s]
      found if found&.available?
    end

    def type_for(model)
      types.values.find { |type| type.model == model }
    end

    # A retention purge (Housekeeping::Purge): admin-run, previewed, never
    # automatic.
    def register_purge(key, **options)
      purge = Purge.new(key, **options)
      purges[purge.key] = purge
      Settings.register(purge.setting, :integer, purge.setting_name, purge.default_months.to_s, "Housekeeping", purge.setting_description)
      purge
    end

    def purges
      @purges ||= {}
    end

    def purge(key)
      found = purges[key.to_s]
      found if found&.available?
    end

    # The purges shown on a list page (the page: option they registered with).
    def purges_for(page)
      purges.values.select { |purge| purge.page == page.to_sym && purge.available? }
    end

    # Something a person does that counts as activity. The block takes a
    # time and returns a relation selecting person_id for activity at or
    # after it:
    #
    #   Housekeeping.register_activity(:checkins) { |since| Checkin.where(created_at: since..).select(:person_id) }
    def register_activity(key, &block)
      activity_sources[key.to_sym] = block
    end

    def activity_sources
      @activity_sources ||= {}
    end

    # People with no activity on or after date, who already existed then.
    def people_without_activity_since(date, scope: Person.all)
      since = date.to_date.in_time_zone.beginning_of_day
      active = activity_sources.values.map { |source| source.call(since) }
      people = scope.where(created_at: ...since)
      active.reduce(people) { |relation, ids| relation.where.not(id: ids) }
    end

    # Archives what's due under each type's "Archive automatically" setting.
    # Records something else still uses are left. Returns { key => [records] }.
    def run(today = Date.current)
      return {} unless enabled?

      types.values.select { |type| type.available? && type.auto_archive? }.to_h do |type|
        archived = type.due(today).reject { |record| type.used_by(record).any? }
        archived.each { |record| type.archive!(record) }
        [ type.key, archived ]
      end
    end

    private

    def register_setting(type)
      Settings.register(type.setting, :integer, "Archive #{type.label} Automatically (days)", "", "Housekeeping",
        "Archive #{type.label.downcase} automatically this many days after they ended. Blank: never")
    end
  end
end
