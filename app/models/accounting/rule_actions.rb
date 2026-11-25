# Applies a rule's actions (AccountingRuleAction) to one person's saved
# result, after each evaluation, whether or not the result changed, so a
# new or edited action reaches everyone on the next run. Only differences
# are written.
#
# Badge: the person has the badge while the condition holds. The rule
# makes the assignment, records it in the result's badge_assignment_id and
# removes only that one; an assignment made by hand is never touched. A
# team badge skips people outside its team, noted in the result's details.
#
# Person field: the label, value or amount is written while the condition
# holds and cleared otherwise, as trusted code (no acting person), and
# "person_fields - value changed" fires for each change.
#
# An error result (a custom rule's code raised) runs no actions and leaves
# what earlier runs did; so does each kind of action while its feature
# (badges, person fields) is off. A result that goes away undoes them
# (#undo) even then, since the result is the only record of what the rule
# gave. Undoing takes back only the badge assignment the result records
# (badge_assignment_id), and clears a field only while it still holds the
# value the result records the rule wrote (details "written_fields", by
# field id) and no other turned-on rule filling that field has a result for
# the person. So a value set by hand, or by a successor rule (a Duplicate
# taking over) for its own people, is left alone, and undoing is safe to
# repeat: turning a rule off and then deleting it undoes once, whichever
# runs first.
class Accounting::RuleActions
  # The result's details key for what an action couldn't do.
  NOTES = "action_notes".freeze
  # The result's details key for the value each field action wrote, as
  # stored, by person field id.
  WRITTEN = "written_fields".freeze
  # Kept from one evaluation to the next, and not part of the outcome.
  KEYS = [ NOTES, WRITTEN ].freeze

  attr_reader :rule

  def initialize(rule)
    @rule = rule
  end

  def apply(result)
    return if result.error?

    notes = []
    written = recorded(result)
    apply_badge(result, notes) if GatherPack::Features.enabled?(:badges)
    if GatherPack::Features.enabled?(:person_fields)
      field_actions.each do |action|
        field = action.person_field
        value = action.holds?(result) ? action.value_for(result) : nil
        next unless write_field(result.person, field, value, notes)

        value.nil? ? written.delete(field.id) : written[field.id] = field.serialize(value)
      end
    end
    record(result, NOTES => notes.presence, WRITTEN => written.presence)
  end

  # Takes back what the rule did for a result about to be removed, or for
  # a rule turned off or deleted.
  def undo(result)
    remove_badge(result)
    written = recorded(result)
    field_actions.each do |action|
      field = action.person_field
      next unless field && written.key?(field.id)
      next unless still_written?(result.person, field, written[field.id]) && !filled_for_person_by_another_rule?(field, result.person_id)

      write_field(result.person, field, nil, [])
    end
    record(result, WRITTEN => nil) if result.persisted? && !result.destroyed?
  end

  private
    def actions
      @actions ||= rule.actions.ordered.includes(:badge, :person_field).to_a
    end

    def badge_action
      actions.find(&:badge?)
    end

    def field_actions
      actions.select(&:person_field?)
    end

    def apply_badge(result, notes)
      action = badge_action
      assignment = result.badge_assignment
      if assignment && (action.nil? || assignment.badge_id != action.badge_id || !action.holds?(result))
        remove_badge(result)
        assignment = nil
      end
      return if action.nil? || assignment || !action.holds?(result)

      badge = action.badge
      person = result.person
      return if BadgeAssignment.exists?(badge: badge, person: person)
      if badge.team && !person.all_teams.include?(badge.team)
        return notes << "Not given #{badge.name}: not on its team, #{badge.team.name}"
      end

      result.update_columns(badge_assignment_id: BadgeAssignment.create!(badge: badge, person: person).id)
    end

    def remove_badge(result)
      assignment = result.badge_assignment
      return unless assignment

      result.update_columns(badge_assignment_id: nil) if result.persisted? && !result.destroyed?
      assignment.destroy!
    end

    # Sets the field to value (nil clears it). Returns whether the field now
    # holds it: false when the field isn't used for the person.
    def write_field(person, field, value, notes)
      return false unless field
      if field.archived? || !field.applies_to?(person)
        notes << "#{field.name} not filled in: it isn't used for this person"
        return false
      end

      current = person.field_value(field)
      new_value = field.cast(field.serialize(value))
      return true if new_value == current

      person.set_field_value(field, value)
      change = PersonFieldChange.new(person: person, field: field, old_value: current, new_value: new_value, changed_by: nil)
      ActiveSupport::Notifications.instrument("person_field_changed.gatherpack", change: change)
      Hook.where(event: "person_fields - value changed").each { |hook| hook.run(change) }
      true
    end

    def recorded(result)
      (result.detail(WRITTEN) || {}).to_h.dup
    end

    # Whether the person's field still holds the value the rule wrote (as
    # stored), not one changed since by hand or by another rule.
    def still_written?(person, field, stored)
      field.cast(stored) == person.field_value(field)
    end

    # Another turned-on rule that fills in the field and gives this person a
    # result writes its own value for them, so it isn't cleared.
    def filled_for_person_by_another_rule?(field, person_id)
      @other_rules ||= {}
      @other_rules[field.id] ||= AccountingRule.enabled.where.not(id: rule.id)
        .where(id: AccountingRuleAction.where(action: "person_field", person_field_id: field.id).select(:rule_id)).ids
      @other_rules[field.id].any? && AccountingRuleResult.where(rule_id: @other_rules[field.id], person_id: person_id).exists?
    end

    # Saves the given details keys (nil removes one), only when they changed.
    def record(result, values)
      details = (result.details || {}).dup
      values.each { |key, value| value.nil? ? details.delete(key) : details[key] = value }
      result.update_columns(details: details) unless details == (result.details || {})
    end
end
