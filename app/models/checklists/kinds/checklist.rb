module Checklists
  module Kinds
    # Finishes another checklist: its overall, read from its stored results.
    # People it doesn't cover are exempt.
    class Checklist < ItemKind
      class << self
        def label = "Another checklist"
        def description = "Finishes another checklist"

        def settings
          [ ItemKind::Setting.new(key: :checklist_id, type: :checklist, label: "Checklist") ]
        end

        def references = { "checklist_id" => "Checklist" }

        # The other checklist's refresh marks this one (Checklists::Refresher).
        def invalidations = []

        def problems(item)
          problems = missing_references(item)
          problems << "No checklist chosen" if item.config["checklist_id"].blank?
          other = referenced_records(item, "checklist_id").first
          problems << "#{other.title} is archived" if other&.archived?
          problems
        end

        def validate(item)
          item.errors.add(:base, "Choose a checklist") if item.config["checklist_id"].blank?
        end

        def describe(item)
          "Finishes #{referenced_records(item, "checklist_id").first&.title || "another checklist"}"
        end

        # The other checklist's overall comes from all its counting items;
        # for a viewer an item there hides from someone, this item is capped
        # for that person too, so it can't carry the hidden answer over.
        def visible_person_ids(item, viewer, person_ids)
          other = referenced_records(item, "checklist_id").first
          return person_ids if other.nil?

          other.top_level_items.includes(children: :children).select(&:counts?).reduce(person_ids.to_a) do |ids, counted|
            ids.any? ? Checklists.visible_person_ids(counted, viewer, ids) : ids
          end
        end
      end

      def evaluate(person_ids)
        other = self.class.referenced_records(item, "checklist_id").first
        return person_ids.index_with { Result.not_met("Checklist missing") } unless other

        statuses = Checklists::Reader.new(other, nil).overall_statuses(person_ids)
        word = ->(status) { other.word_for(status) }

        person_ids.index_with do |person_id|
          status = statuses[person_id]
          next Result.exempt("Not on #{other.title}") if status.nil?

          Result.new(status: status, summary: "#{other.title}: #{word.call(status)}",
            fix: status == "met" ? nil : { "label" => "See #{other.title}", "path" => "/checklists/#{other.to_param}" })
        end
      end
    end
  end
end
