# Takes back what a turned-off rule's actions gave (AccountingRule#undo_actions).
# Shares Accounting::EvaluateRuleJob's concurrency key, so it waits for an
# evaluation of the same rule already running, which would otherwise give
# badges back after the undo. Does nothing if the rule was turned on again
# before it ran, or deleted.
class Accounting::UndoRuleActionsJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(rule, *) { rule.id }, group: Accounting::EvaluateRuleJob::CONCURRENCY_GROUP

  discard_on ActiveJob::DeserializationError

  def perform(rule)
    rule.reload
    return if rule.enabled?

    rule.undo_actions
  end
end
