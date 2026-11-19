module Checklists
  # Whether a checklist rule on a sign-up position asks for something that
  # signing up there is how people get: the position's sheet or the
  # position itself is a credit source of a count item in the checklist, or
  # the sheet's event type, or that of an event the position has places
  # at, is a check-in source of one. Then only people
  # who already finished can sign up. The rules controller warns when such
  # a rule is saved, unless it also lets people partway through.
  # Checklists the rule's checklist wraps aren't looked into.
  class SignupRuleLoop
    def initialize(rule)
      @rule = rule
    end

    def warning
      return unless loop?

      title = @rule.checklist.title
      "Signing up here counts toward #{title}, so requiring it first means only people who already finished can sign up. " \
        "Turn on 'Also allow people partway through' or drop the rule."
    end

    def loop?
      return false unless @rule.checklist? && @rule.checklist && !@rule.accept_pending?

      position = @rule.signup_position
      sheet = position.signup_sheet
      sources = CommitmentSource.where(commitment_id: @rule.checklist.checklist_items.where(kind: Checklists::CountItem::COUNT).select(:commitment_id))
      subjects = sources.where(subject_type: "SignupSheet", subject_id: sheet.id).or(sources.where(subject_type: "SignupPosition", subject_id: position.id))
      event_type_ids = Event.where(id: position.signup_slots.select(:event_id)).where.not(event_type_id: nil).distinct.pluck(:event_type_id)
      event_type_ids |= [ sheet.event_type_id ] if sheet.event_type_id
      subjects = subjects.or(sources.where(subject_type: "EventType", subject_id: event_type_ids)) if event_type_ids.any?
      subjects.exists?
    end
  end
end
