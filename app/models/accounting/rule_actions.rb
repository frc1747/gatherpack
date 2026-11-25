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
# what earlier runs did. A result that goes away undoes them (#undo).
class Accounting::RuleActions
  # The result's details key for what an action couldn't do.
  NOTES = "action_notes".freeze

  attr_reader :rule

  def initialize(rule)
    @rule = rule
  end

  def apply(result)
    return if result.error?

    notes = []
    apply_badge(result, notes)
    field_actions.each { |action| write_field(result.person, action.person_field, action.holds?(result) ? action.value_for(result) : nil, notes) }
    record_notes(result, notes)
  end

  # Takes back what the rule did for a result about to be removed.
  def undo(result)
    remove_badge(result)
    field_actions.each { |action| write_field(result.person, action.person_field, nil, []) }
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

    def write_field(person, field, value, notes)
      return unless field
      if field.archived? || !field.applies_to?(person)
        return notes << "#{field.name} not filled in: it isn't used for this person"
      end

      current = person.field_value(field)
      new_value = field.cast(field.serialize(value))
      return if new_value == current

      person.set_field_value(field, value)
      change = PersonFieldChange.new(person: person, field: field, old_value: current, new_value: new_value, changed_by: nil)
      ActiveSupport::Notifications.instrument("person_field_changed.gatherpack", change: change)
      Hook.where(event: "person_fields - value changed").each { |hook| hook.run(change) }
    end

    def record_notes(result, notes)
      return if Array(result.detail(NOTES)) == notes

      details = (result.details || {}).except(NOTES)
      result.update_columns(details: notes.any? ? details.merge(NOTES => notes) : details)
    end
end
