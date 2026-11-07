# Checklists and forms together: the form item kind, and the form audience
# target "checklist" (people a checklist covers, or who have or haven't
# finished it). Registers only when both features' code is present.
Rails.application.config.to_prepare do
  next unless defined?(Checklists) && Checklists.respond_to?(:register_item_kind) && defined?(FormAudienceRule)

  Checklists.register_item_kind(:form_complete, Checklists::Kinds::FormComplete)

  FormAudienceRule.prepend(Checklists::FormAudienceTarget) unless FormAudienceRule < Checklists::FormAudienceTarget
  FormAudienceRulePolicy.prepend(Checklists::FormAudienceRuleAccess) unless FormAudienceRulePolicy < Checklists::FormAudienceRuleAccess
  FormAudienceRulesController.prepend(Checklists::FormAudienceRuleParams) unless FormAudienceRulesController < Checklists::FormAudienceRuleParams
  Form.prepend(Checklists::FormOpenable) unless Form < Checklists::FormOpenable
  Form.include(Checklists::FormAudienceTeamGuard::OnForm) unless Form < Checklists::FormAudienceTeamGuard::OnForm
  Checklist.include(Checklists::FormAudienceTeamGuard::OnChecklist) unless Checklist < Checklists::FormAudienceTeamGuard::OnChecklist
  ChecklistItem.include(Checklists::FormRequirementGuard) unless ChecklistItem < Checklists::FormRequirementGuard
  ChecklistRule.include(Checklists::FormAudienceRefresh::RuleChanges) unless ChecklistRule < Checklists::FormAudienceRefresh::RuleChanges
  Checklists::Refresher.prepend(Checklists::FormAudienceRefresh::OverallChanges) unless Checklists::Refresher < Checklists::FormAudienceRefresh::OverallChanges

  # A checklist a form asks can't be deleted while it does.
  Checklist.has_many :form_audience_rules, dependent: :restrict_with_error
end
