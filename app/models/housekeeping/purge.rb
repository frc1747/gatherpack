module Housekeeping
  # A retention purge (Housekeeping.register_purge): data older than an age
  # an admin removes by hand, after seeing exactly what will go. Nothing runs
  # by itself. Each run is logged as a HousekeepingPurge (audited).
  #
  # Options:
  # - label: what goes, as a plural ("Denied applications").
  # - page: the list page it's offered on (:membership_applications, :people).
  # - default_months: the age setting's default. Blank in settings disables it.
  # - records: ->(cutoff_date) { relation } of what would go.
  # - describe: ->(records) { [[heading, detail], ...] } for the preview.
  # - rows: ->(records) { how many rows describe gives in all }, when that
  #   isn't one per record (one per person, say). Default: the count.
  # - summary: ->(records) { "2 answers from 1 person" }, what will go.
  #   Default: the count.
  # - apply: ->(records) { ... } removes them. Default: delete_all, and their
  #   audit rows, which hold the same data.
  # - available: -> { true/false }.
  class Purge
    attr_reader :key, :label, :page, :default_months

    def initialize(key, label:, page:, records:, default_months:, describe: nil, rows: nil, summary: nil, apply: nil, available: nil,
      description: nil)
      @key = key.to_s
      @label = label
      @page = page.to_sym
      @records = records
      @default_months = default_months
      @describe = describe
      @rows = rows
      @summary = summary
      @apply = apply
      @available = available
      @description = description
    end

    def available?
      Housekeeping.enabled? && (@available.nil? || @available.call)
    end

    def setting
      :"housekeeping_purge_#{key}_months"
    end

    def setting_name
      "Clear #{label} After (months)"
    end

    def setting_description
      "#{@description || label} older than this many months can be cleared by an admin, after a preview. Nothing is cleared automatically. Blank: off"
    end

    # Months from the setting; nil when it's blank (the purge is off).
    def months
      value = Settings[setting].to_s.strip
      value.to_i if value.match?(/\A\d+\z/)
    end

    def enabled?
      !months.nil?
    end

    # The date the setting gives: older than this goes.
    def default_cutoff(today = Date.current)
      today - months.months if enabled?
    end

    def records(cutoff)
      @records.call(cutoff)
    end

    def describe(records)
      @describe ? @describe.call(records) : records.map { |record| [ record.try(:identifier_name) || record.to_s, nil ] }
    end

    # How many rows describe gives for all of records.
    def row_count(records)
      @rows ? @rows.call(records) : records.count
    end

    def summary(records)
      @summary ? @summary.call(records) : records.count.to_s
    end

    # Removes everything older than cutoff and logs who did it. Returns the
    # HousekeepingPurge.
    def run!(cutoff:, by:)
      raise ArgumentError, "#{label} can't be cleared: the setting is blank" unless enabled?

      gone = records(cutoff)
      count = gone.count
      ids = gone.ids
      HousekeepingPurge.transaction do
        @apply ? @apply.call(gone) : Purge.delete_with_audit(gone.model.where(id: ids))
        HousekeepingPurge.create!(key: key, cutoff_on: cutoff, count: count, person: by)
      end
    end

    # Deletes the rows without writing new audit rows (a destroy entry would
    # keep the data), and removes their old audit rows.
    def self.delete_with_audit(relation)
      model = relation.model
      ids = relation.ids
      relation.delete_all
      AuditLog.where(item_type: model.name, item_id: ids).delete_all if ids.any?
      ids.size
    end
  end
end
