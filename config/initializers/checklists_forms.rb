# Checklists and forms together: the form item kind, and the form audience
# target "checklist" (people a checklist covers, or who have or haven't
# finished it). Registers only when both features' code is present.
Rails.application.config.to_prepare do
  next unless defined?(Checklists) && Checklists.respond_to?(:register_item_kind) && defined?(FormAudienceRule)

  Checklists.register_item_kind(:form_complete, Checklists::Kinds::FormComplete)
  ChecklistItemsController.prepend(Checklists::FormItemParams) unless ChecklistItemsController < Checklists::FormItemParams

  FormAudienceRule.prepend(Checklists::FormAudienceTarget) unless FormAudienceRule < Checklists::FormAudienceTarget
  FormAudienceRulePolicy.prepend(Checklists::FormAudienceRuleAccess) unless FormAudienceRulePolicy < Checklists::FormAudienceRuleAccess
  FormAudienceRulesController.prepend(Checklists::FormAudienceRuleParams) unless FormAudienceRulesController < Checklists::FormAudienceRuleParams

  # A checklist a form asks can't be deleted while it does.
  Checklist.has_many :form_audience_rules, dependent: :restrict_with_error
end
