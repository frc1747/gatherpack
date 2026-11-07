module Checklists
  # Stops a checklist a sign-up position rule needs from being deleted, with
  # a readable error (the foreign key blocks it too). Included in Checklist
  # by config/initializers/checklists_signups.rb.
  module UsedBySignupRules
    extend ActiveSupport::Concern

    included do
      has_many :signup_position_rules
      before_destroy :refuse_while_signup_rules_use, prepend: true
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
