module Checklists
  # Prepended to Checklists::Refresher (config/initializers/checklists_count.rb):
  # each refresh first writes count items' resolved dates into their
  # commitments' starts_on and ends_on, so relative dates and cutoffs show
  # there too (checklists spec §6.2). Counting itself reads the item's dates
  # directly (Checklists::CountCommitment#period_times).
  module CountPeriods
    def call(...)
      Checklists::Kinds::Count.sync_periods(checklist) unless checklist.archived?
      super
    end
  end
end
