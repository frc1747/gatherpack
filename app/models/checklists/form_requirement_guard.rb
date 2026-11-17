module Checklists
  # A form asking only the people who have (or haven't) finished a checklist
  # must not be one that checklist requires, directly or through checklists
  # it requires: its answer would feed itself, and nobody could finish.
  # Checked from both sides, the audience rule (Checklists::FormAudienceTarget)
  # and the item (included in ChecklistItem), whichever comes second.
  module FormRequirementGuard
    extend ActiveSupport::Concern

    included do
      validate :no_form_asking_by_this_checklist
    end

    # Whether the checklist, or one it requires, has a form item for the form.
    def self.requires_form?(checklist, form_id)
      ids = ChecklistItem.reachable_checklist_ids([ checklist.id ])
      ChecklistItem.where(checklist_id: ids.to_a, kind: "form_complete").any? { |item| Array(item.config["form_ids"]).include?(form_id.to_s) }
    end

    private

    # This item makes its checklist require forms: those it names, or those
    # the checklist it points to requires. A rule asking by status on this
    # checklist, or on one that requires it, can't name any of them.
    def no_form_asking_by_this_checklist
      return unless checklist_id

      form_ids = case kind
      when "form_complete" then Array(config["form_ids"]).compact_blank
      when "checklist" then forms_required_by(config["checklist_id"])
      else []
      end
      return if form_ids.empty?

      rules = FormAudienceRule.where(target_type: :checklist, checklist_match: %i[ met not_met ], form_id: form_ids).includes(:form, :checklist)
      clash = rules.detect { |rule| rule.checklist && ChecklistItem.reachable_checklist_ids([ rule.checklist_id ]).include?(checklist_id) }
      return unless clash

      errors.add(:base, "#{clash.form.title} asks only people who have or haven't finished #{clash.checklist.title}, " \
        "so #{clash.checklist.title} can't require it")
    end

    def forms_required_by(other_id)
      return [] if other_id.blank?

      ids = ChecklistItem.reachable_checklist_ids([ other_id ])
      ChecklistItem.where(checklist_id: ids.to_a, kind: "form_complete").flat_map { |item| Array(item.config["form_ids"]) }.uniq
    end
  end
end
