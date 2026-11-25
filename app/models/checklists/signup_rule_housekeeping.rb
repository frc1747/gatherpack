module Checklists
  # Keeps nightly housekeeping from archiving a checklist a sign-up sheet
  # (not archived) still needs, as it already does for one another
  # checklist requires: archived checklists stop refreshing and later lose
  # their results, which would refuse everyone the place. ignoring_signups:
  # asks whether it would be due otherwise (for the problem note).
  # Prepended to Checklists::Housekeeping's class methods by
  # config/initializers/checklists_signups.rb.
  module SignupRuleHousekeeping
    def archive_due?(checklist, today = Date.current, ignoring_signups: false)
      return false unless super(checklist, today)

      ignoring_signups || !checklist.signup_sheets_needing.exists?
    end

    # Where archiving reads what still uses a checklist (the Housekeeping
    # pattern's checklist type, when it's there), the sheets count too.
    def used_by(checklist)
      names = defined?(super) ? super : []
      names + checklist.signup_sheets_needing.order(:title).pluck(:title).map { |title| "the sign-up sheet #{title}" }
    end
  end
end
