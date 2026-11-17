module Checklists
  # Stops a team, badge or other record a checklist uses from being deleted
  # while it's used, with a readable error: a checklist's own team, a rule's
  # or grant's team or badge, and records an item's config names. Installed
  # on Team and Badge, and on each model a kind references when the kind
  # registers. With the feature off it does nothing (the foreign keys still
  # protect a checklist's team and its rules' and grants' targets).
  module ProtectsReferences
    extend ActiveSupport::Concern

    included do
      before_destroy :refuse_while_checklist_uses, prepend: true
    end

    def self.install(kind)
      kind.references.each_value { |model_name| install_model(model_name.constantize) }
    end

    def self.install_model(model)
      model.include(self) unless model < self
    end

    private

    def refuse_while_checklist_uses
      return unless Checklists.enabled?

      titles = Checklist.where(id: checklist_ids_using_this).pluck(:title)
      return if titles.empty?

      errors.add(:base, "Used by the checklist#{"s" if titles.size > 1} #{titles.uniq.to_sentence}; take it off there first")
      throw :abort
    end

    def checklist_ids_using_this
      ids = []
      case self
      when ::Team
        ids += Checklist.where(team_id: id).ids
        ids += ChecklistRule.where(team_id: id).pluck(:checklist_id) + ChecklistGrant.where(team_id: id).pluck(:checklist_id)
      when ::Badge
        ids += ChecklistRule.where(badge_id: id).pluck(:checklist_id) + ChecklistGrant.where(badge_id: id).pluck(:checklist_id)
      end

      name = self.class.name
      keys = Checklists.item_kinds.values.flat_map { |kind| kind.references.select { |_, model| model == name }.keys }.uniq
      if keys.any?
        items = keys.map { |key| ChecklistItem.where("jsonb_exists(COALESCE(config -> :key, '[]'::jsonb), :id) OR config ->> :key = :id", key: key, id: id.to_s) }.reduce(:or)
        ids += items.pluck(:checklist_id)
      end
      ids.uniq
    end
  end
end
