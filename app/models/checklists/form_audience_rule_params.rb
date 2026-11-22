module Checklists
  # Lets a form audience rule name a checklist and which of its people to
  # ask. Prepended to FormAudienceRulesController.
  module FormAudienceRuleParams
    private

    def rule_params
      super.merge(params.require(:form_audience_rule).permit(:checklist_id, :checklist_match))
    end
  end
end
