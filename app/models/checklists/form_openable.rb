module Checklists
  # While checklists are turned off a checklist audience rule asks nobody,
  # so it doesn't make a form openable. Prepended to Form.
  module FormOpenable
    def openable?
      return super if Checklists.enabled?

      form_audience_rules.any? { |rule| rule.effect_include? && !rule.target_checklist? && (!rule.target_badge? || Form.badges_enabled?) }
    end
  end
end
