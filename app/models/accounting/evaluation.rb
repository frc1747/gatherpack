# Recomputes a rule's results (Accounting::Kinds) and saves only what
# changed. A turned-off rule isn't worked out (a draft, such as a
# Duplicate, mustn't fire hooks); its results are when it's turned on.
# Turning a rule off takes back what its actions gave (AccountingRule), and
# the next run after it's turned on gives it again. A run checks the rule is
# still on before each person's actions, and stops, firing no hooks, once
# it's been turned off.
# Each person's actions (Accounting::RuleActions) are applied after their
# result is saved. A change of value or amount fires "accounting_rules -
# result changed" with an AccountingRuleChange, after the results are saved
# and the actions ran. People who no longer qualify (AccountingRule#people)
# lose their result and the rule's actions undo, which fires the event too,
# with no new value.
class Accounting::Evaluation
  EVENT = "accounting_rules - result changed".freeze

  attr_reader :rule, :today

  def initialize(rule, today: Date.current)
    @rule = rule
    @today = today
    @records = Accounting::RuleRecords.new(rule)
    @actions = Accounting::RuleActions.new(rule)
  end

  # The outcome for one person, without saving it (Preview uses this).
  def outcome_for(person)
    Accounting::Kinds.for(rule.kind).new(rule, person, records: @records, today: today).evaluate
  end

  # Evaluates everyone the rule applies to, or only the given people.
  # Returns the AccountingRuleChange of each result that changed.
  def run(person_ids = nil)
    return [] unless rule.enabled? && rule.evaluable?

    people = rule.people
    people = people.where(id: person_ids) if person_ids
    existing = rule.results.where(person_id: people.select(:id)).includes(:badge_assignment).index_by(&:person_id)
    now = Time.current
    unchanged = []

    changes = []
    people.find_each do |person|
      outcome = outcome_for(person)
      result = existing[person.id]
      if result && same?(result, outcome)
        unchanged << result.id
        result.person = person
      else
        result ||= rule.results.build(person: person)
        change = save(result, outcome, now)
        changes << change if change
      end
      return [] unless still_enabled?

      @actions.apply(result)
    end
    AccountingRuleResult.where(id: unchanged).update_all(evaluated_at: now) if unchanged.any?
    changes += remove_unqualified(person_ids)

    hooks = Hook.where(event: EVENT).to_a
    changes.each { |change| hooks.each { |hook| hook.run(change) } } if hooks.any?
    changes
  end

  private
    # Turned off since the run started: Accounting::UndoRuleActionsJob takes
    # back what the actions gave, so they mustn't give more.
    def still_enabled?
      AccountingRule.where(id: rule.id, enabled: true).exists?
    end

    def same?(result, outcome)
      result.value == outcome.value && result.amount_cents == outcome.amount_cents &&
        (result.details || {}).except(*Accounting::RuleActions::KEYS) == outcome.stored_details.except(*Accounting::RuleActions::KEYS)
    end

    # Saves the outcome; returns the change when the value or amount moved.
    def save(result, outcome, now)
      old_value = result.new_record? ? nil : result.value
      old_amount = result.new_record? ? nil : result.amount_cents
      moved = result.new_record? || old_value != outcome.value || old_amount != outcome.amount_cents
      # What the actions wrote stays recorded (Accounting::RuleActions).
      kept = (result.details || {}).slice(Accounting::RuleActions::WRITTEN)
      result.assign_attributes(value: outcome.value, amount_cents: outcome.amount_cents, details: outcome.stored_details.merge(kept), evaluated_at: now)
      result.changed_at = now if moved
      result.save!
      return nil unless moved

      change_for(result.person, old_value, outcome.value, old_amount, outcome.amount_cents, result)
    end

    def remove_unqualified(person_ids)
      stale = rule.results.where.not(person_id: rule.people.select(:id)).includes(:person)
      stale = stale.where(person_id: person_ids) if person_ids
      stale = stale.includes(:badge_assignment)
      stale.map do |result|
        @actions.undo(result)
        result.destroy!
        change_for(result.person, result.value, nil, result.amount_cents, nil, result)
      end
    end

    def change_for(person, old_value, new_value, old_amount, new_amount, result)
      AccountingRuleChange.new(rule: rule, person: person, old_value: old_value, new_value: new_value,
        old_amount_cents: old_amount, new_amount_cents: new_amount,
        unapplied_credit_cents: result.unapplied_credit_cents, on_plan: result.on_plan?)
    end
end
