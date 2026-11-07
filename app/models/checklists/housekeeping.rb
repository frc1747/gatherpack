module Checklists
  # Clearing stored results of archived checklists (spec §9.7), run nightly
  # by ChecklistNightlyJob. Archiving checklists by date is the Housekeeping
  # pattern's job (the "checklists" type, HousekeepingNightlyJob), which
  # also reads the older checklists_archive_after setting.
  #
  # checklists_prune_results_after: a date (YYYY-MM-DD) or a number of days
  # after a checklist's end; blank means never. Archived checklists that
  # ended before it lose their stored results. Results are a cache; recorded
  # lists and audit rows stay.
  module Housekeeping
    class << self
      def run(today = Date.current)
        pruned = Checklist.archived.where.not(ends_on: nil).select { |checklist| due?(:checklists_prune_results_after, checklist, today) }
        pruned.each { |checklist| checklist.checklist_results.delete_all }
        { pruned: pruned }
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
