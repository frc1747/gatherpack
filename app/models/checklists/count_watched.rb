module Checklists
  # Included in the models Checklists::Kinds::Count::WATCHED names
  # (config/initializers/checklists_count.rb). After a change commits, marks
  # the count checklists it can affect (Checklists::Kinds::Count.changed),
  # so a check-in nobody counts touches nothing. With checklists off nothing
  # happens, and a failure is logged, never raised into the save.
  module CountWatched
    extend ActiveSupport::Concern

    included do
      after_commit :mark_count_checklists
    end

    private

    def mark_count_checklists
      return unless Checklists.enabled?

      Checklists::Kinds::Count.changed(self)
    rescue StandardError => e
      Rails.logger.error("Checklists couldn't mark count items after a #{self.class.name} change: #{e.class}: #{e.message}")
    end
  end
end
