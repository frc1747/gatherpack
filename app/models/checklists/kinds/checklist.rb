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

        reader = Checklists::Reader.new(other, nil)
        rows = reader.rows(person_ids)
        counting = reader.items.select(&:counts?).map(&:id)
        word = ->(status) { other.word_for(status) }

        person_ids.index_with do |person_id|
          status = rows.dig(person_id, nil)&.status
          next Result.exempt("Not on #{other.title}") if status.nil?

          fix = { "label" => "See #{other.title}", "path" => "/checklists/#{other.to_param}",
            "by" => who_acts(rows[person_id].values_at(*counting).compact) }.compact
          Result.new(status: status, summary: "#{other.title}: #{word.call(status)}", fix: status == "met" ? nil : fix)
        end
      end

      private

      # Who acts on the other checklist's counting items that aren't done,
      # from the same rows as its overall: "person" when any is the person's,
      # else "guardian" when any is a guardian's, else "leader". Nil when
      # none says who acts.
      def who_acts(rows)
        by = rows.select { |row| %w[not_met pending].include?(row.status) }.filter_map { |row| row.fix&.dig("by") }
        %w[person guardian leader].find { |who| by.include?(who) }
      end
    end
  end
end
