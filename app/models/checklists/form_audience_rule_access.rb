module Checklists
  # A form manager may ask a checklist's people when they run that checklist
  # (its organizers, managers of its team, admins). Prepended to
  # FormAudienceRulePolicy.
  module FormAudienceRuleAccess
    private

    def targetable?
      return super unless record.target_checklist?
      return true if user.admin

      record.checklist.present? && ChecklistPolicy.new(user, record.checklist).update?
    end
  end
end
