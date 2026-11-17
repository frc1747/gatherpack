module Checklists
  # Date housekeeping (spec §9.7), run nightly by ChecklistNightlyJob. Two
  # optional settings, each a date (YYYY-MM-DD) or a number of days after a
  # checklist's end; blank means never:
  #
  # - checklists_archive_after: active checklists that ended before it are
  #   archived. One another (not archived) checklist requires is skipped and
  #   shown as a problem on it.
  # - checklists_prune_results_after: archived checklists that ended before it
  #   lose their stored results. Results are a cache; recorded lists and
  #   audit rows stay.
  module Housekeeping
    class << self
      def run(today = Date.current)
        archived = Checklist.active.where.not(ends_on: nil).select { |checklist| archive_due?(checklist, today) }
          .reject { |checklist| checklist.dependents.refreshable.exists? }
        archived.each { |checklist| checklist.update!(status: :archived) }

        pruned = Checklist.archived.where.not(ends_on: nil).select { |checklist| due?(:checklists_prune_results_after, checklist, today) }
        pruned.each { |checklist| checklist.checklist_results.delete_all }
        { archived: archived, pruned: pruned }
      end

      def archive_due?(checklist, today = Date.current)
        due?(:checklists_archive_after, checklist, today)
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
