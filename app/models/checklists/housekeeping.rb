module Checklists
  # Date housekeeping for checklists (spec §9.7), run nightly by
  # ChecklistNightlyJob. Archiving checklists by date is the Housekeeping
  # pattern's job (the "checklists" type): HousekeepingNightlyJob while
  # Housekeeping is on, and here, under the older checklists_archive_after
  # setting, while it's off (Housekeeping.run_fallback). A checklist another
  # (not archived) one requires is skipped and shown as a problem on it.
  #
  # checklists_prune_results_after: a date (YYYY-MM-DD) or a number of days
  # after a checklist's end; blank means never. Archived checklists that
  # ended before it lose their stored results. Results are a cache; recorded
  # lists and audit rows stay.
  module Housekeeping
    class << self
      def run(today = Date.current)
        archived = ::Housekeeping.run_fallback(:checklists, today)
        pruned = Checklist.archived.where.not(ends_on: nil).select { |checklist| due?(:checklists_prune_results_after, checklist, today) }
        pruned.each { |checklist| checklist.checklist_results.delete_all }
        { archived: archived, pruned: pruned }
      end

      # [:date, Date], [:days, Integer] or nil.
      def parse(value)
        value = value.to_s.strip
        return if value.blank?
        return [ :days, value.to_i ] if value.match?(/\A\d+\z/)

        [ :date, Date.iso8601(value) ]
      rescue Date::Error
        nil
      end

      private

      def due?(setting, checklist, today)
        return false if checklist.ends_on.nil?

        type, value = parse(Settings[setting])
        case type
        when :date then checklist.ends_on < value
        when :days then checklist.ends_on + value.days < today
        else false
        end
      end
    end
  end
end
