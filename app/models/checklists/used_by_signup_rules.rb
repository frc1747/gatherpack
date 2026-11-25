module Checklists
  # A checklist a sign-up position rule needs is in use: it can't be
  # deleted (a readable error; the foreign key blocks it too), and nightly
  # housekeeping doesn't archive it while a sheet that isn't archived needs
  # it (Checklists::SignupRuleHousekeeping), which shows as a problem on it.
  # Prepended to Checklist by config/initializers/checklists_signups.rb.
  module UsedBySignupRules
    extend ActiveSupport::Concern

    prepended do
      has_many :signup_position_rules
      before_destroy :refuse_while_signup_rules_use, prepend: true
    end

    # The sign-up sheets, not archived, with a position needing this.
    def signup_sheets_needing
      SignupSheet.where.not(status: :archived)
        .where(id: SignupPosition.where(id: signup_position_rules.select(:signup_position_id)).select(:signup_sheet_id))
    end

    # Housekeeping's "Ended, but not archived" note covers both what holds
    # it back: checklists requiring it and sheets needing it.
    def problems
      list = super
      return list unless active? && Checklists::Housekeeping.archive_due?(self, ignoring_signups: true)

      sheets = signup_sheets_needing.order(:title).pluck(:title)
      return list if sheets.empty?

      needing = dependents.refreshable.pluck(:title) + sheets.map { |title| "the sign-up sheet #{title}" }
      list << "Ended, but not archived: #{needing.to_sentence} still #{needing.size > 1 ? "need" : "needs"} it"
    end

    private

    def refuse_while_signup_rules_use
      positions = SignupPosition.where(id: signup_position_rules.select(:signup_position_id)).includes(:signup_sheet)
      return if positions.empty?

      names = positions.map { |position| "#{position.signup_sheet.title} (#{position.name})" }.uniq
      errors.add(:base, "Sign-up sheet#{"s" if names.size > 1} #{names.to_sentence} #{names.size > 1 ? "need" : "needs"} it; take it off there first")
      throw :abort
    end
  end
end
