module Checklists
  # Keeps form items right when a form asks a checklist's people (§8.2). A
  # form whose audience names checklist C asks different people when C's
  # population rules change, or (for "have finished" and "haven't
  # finished") when someone's overall on C changes. Checklists with a form
  # item for that form are then marked, as the form's own changes mark them.
  module FormAudienceRefresh
    # Prepended to Checklists::Refresher: after an overall changes.
    module OverallChanges
      private

      def mark_dependents(changes)
        super
        person_ids = changes.select { |row| row.item_id.nil? }.map(&:person_id)
        FormAudienceRefresh.mark(checklist, person_ids, matches: %w[ met not_met ]) if person_ids.any?
      end
    end

    # Included in ChecklistRule: after a population rule changes.
    module RuleChanges
      extend ActiveSupport::Concern

      included do
        after_commit :mark_form_audience_checklists, if: -> { item_id.nil? }
      end

      private

      def mark_form_audience_checklists
        return unless Checklists.enabled? && (changed_checklist = Checklist.find_by(id: checklist_id))

        FormAudienceRefresh.mark(changed_checklist, :all)
      rescue StandardError => e
        Rails.logger.error("Checklists couldn't mark form items after a checklist rule change: #{e.class}: #{e.message}")
      end
    end

    # Marks these people on every checklist with a form item for a form
    # whose audience names this checklist (with one of these matches).
    def self.mark(checklist, person_ids, matches: nil)
      rules = FormAudienceRule.where(target_type: :checklist, checklist_id: checklist.id)
      rules = rules.where(checklist_match: matches) if matches
      form_ids = rules.distinct.pluck(:form_id)
      return if form_ids.empty?

      items = ChecklistItem.where(kind: "form_complete")
        .where("jsonb_exists_any(COALESCE(config -> 'form_ids', '[]'::jsonb), ARRAY[:ids]::text[])", ids: form_ids.map(&:to_s))
      Checklists.mark(Checklist.refreshable.where(id: items.select(:checklist_id)).to_a, person_ids)
    end
  end
end
