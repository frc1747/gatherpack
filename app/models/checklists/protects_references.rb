module Checklists
  # Stops a badge, team or other record an item's config names from being
  # deleted while an item uses it, with a readable error (the rules' foreign
  # keys do the same for rule targets). Installed on each model a kind
  # references when the kind registers.
  module ProtectsReferences
    extend ActiveSupport::Concern

    included do
      before_destroy :refuse_while_checklist_uses
    end

    def self.install(kind)
      kind.references.each_value do |model_name|
        model = model_name.constantize
        model.include(self) unless model < self
      end
    end

    private

    def refuse_while_checklist_uses
      name = self.class.name
      keys = Checklists.item_kinds.values.flat_map { |kind| kind.references.select { |_, model| model == name }.keys }.uniq
      return if keys.empty?

      items = keys.map { |key| ChecklistItem.where("jsonb_exists(COALESCE(config -> :key, '[]'::jsonb), :id) OR config ->> :key = :id", key: key, id: id.to_s) }.reduce(:or)
      titles = Checklist.where(id: items.select(:checklist_id)).pluck(:title)
      return if titles.empty?

      errors.add(:base, "Used by the checklist#{"s" if titles.size > 1} #{titles.to_sentence}; take it off there first")
      throw :abort
    end
  end
end
