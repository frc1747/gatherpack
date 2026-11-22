module Checklists
  # A form manager may ask a checklist's people when they run that checklist
  # (its organizers, managers of its team, admins), while checklists are on
  # and the checklist isn't archived. Prepended to FormAudienceRulePolicy.
  module FormAudienceRuleAccess
    private

    def targetable?
      return super unless record.target_checklist?
      return false unless Checklists.enabled? && record.checklist.present? && !record.checklist.archived?

      user.admin || ChecklistPolicy.new(user, record.checklist).update?
    end
  end
end
