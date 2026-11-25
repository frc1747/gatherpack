# Recomputes one rule's results: for the given people (after a sync or a
# link change touched them), or everyone (after the rule changed, on
# Evaluate now, and nightly). Does nothing while the feature is off.
class Accounting::EvaluateRuleJob < ApplicationJob
  queue_as :default

  # Shared with Accounting::UndoRuleActionsJob: one job per rule at a time.
  CONCURRENCY_GROUP = "accounting_rule".freeze

  limits_concurrency to: 1, key: ->(rule, *) { rule.id }, group: CONCURRENCY_GROUP

  discard_on ActiveJob::DeserializationError

  def perform(rule, person_ids = nil)
    return unless Accounting.enabled?

    Accounting::Evaluation.new(rule).run(person_ids)
  end

  # Queues evaluation of every enabled rule of a source, for the given
  # people (nil for everyone).
  def self.for_source(source, person_ids = nil)
    return if person_ids&.empty?

    AccountingRule.enabled.where(gateway_id: source.id).find_each { |rule| perform_later(rule, person_ids) }
  end
end
