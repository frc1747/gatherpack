module Checklists
  module Kinds
    # Finishes another checklist: its overall, read from its stored results,
    # or computed as of this checklist's moment once this one has frozen.
    # People it doesn't cover are exempt.
    class Checklist < ItemKind
      class << self
        def label = "Another checklist"
        def description = "Finishes another checklist"

        def settings
          [ ItemKind::Setting.new(key: :checklist_id, type: :checklist, label: "Checklist") ]
        end

        def references = { "checklist_id" => "Checklist" }

        # Passed through from the other checklist's one counted item when it
        # measures progress (see passes_progress?).
        def measures
          [
            ItemKind::Measure.new(key: "confirmed", label: "Done", type: :number),
            ItemKind::Measure.new(key: "owed", label: "Needed", type: :number)
          ]
        end

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

        # The other checklist's one counted item, as viewer sees it on person's
        # results, when this item passes its counts through (see
        # passes_progress?); else nil. Its kind's detail_partial fills this
        # item's Details too.
        def inner_entry(item, person, viewer)
          other = referenced_records(item, "checklist_id").first
          return if other.nil?

          counted = other.top_level_items.select(&:counts?)
          return unless counted.one? && counted.first.kind_class.present? && !counted.first.kind_class.limits_detail?

          Checklists.status_for(other, [ person ], viewer: viewer)[person.id]&.item(counted.first.id)
        end

        def detail_partial = "checklists/kinds/checklist_detail"

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

        reader = context.pinned? ? Checklists::Reader.new(other, nil, as_of: context.as_of, pinned: true) : Checklists::Reader.new(other, nil)
        rows = reader.rows(person_ids)
        counting = reader.items.select(&:counts?).map(&:id)
        pass_progress = passes_progress?(reader)
        people = pass_progress ? {} : ::Person.where(id: person_ids).index_by(&:id)

        person_ids.index_with do |person_id|
          status = rows.dig(person_id, nil)&.status
          next Result.exempt(item.exempt_label.presence || "Not on #{other.title}") if status.nil?

          counted_rows = rows[person_id].values_at(*counting)
          fix = if status == "met" then nil
          elsif pass_progress then inner_fix(other, reader.items.find(&:counts?), counted_rows.first)
          else card_fix(other, people[person_id], counted_rows.compact)
          end
          Result.new(status: status, summary: "#{other.title}: #{other.word_for(status)}", fix: fix,
            measures: pass_progress ? progress(counted_rows) : {})
        end
      end

      private

      # When the other checklist counts exactly one item and that item
      # measures progress (confirmed of owed), its numbers pass through, so
      # this item shows the same count and bar instead of a bare status. Not
      # from a kind that limits who sees its details (attendance hours):
      # this item couldn't keep that limit.
      def passes_progress?(reader)
        counted = reader.items.select(&:counts?)
        counted.one? && counted.first.kind_class.present? && !counted.first.kind_class.limits_detail?
      end

      # The counted item's own fix ("Next: ..."), so the line leads where
      # that item would. A confirm names its item and checklist, since it
      # posts there.
      def inner_fix(other, counted, row)
        fix = row&.fix
        return if fix.blank?
        return fix unless fix["action"] == "attest"

        fix.merge("item_id" => fix["item_id"] || counted.id, "checklist_id" => other.id)
      end

      # A link to the other checklist's card on the person's own checklists
      # page, which says what is left there.
      def card_fix(other, person, counted_rows)
        return if person.nil?

        path = Rails.application.routes.url_helpers.person_checklists_path(person, anchor: ActionView::RecordIdentifier.dom_id(other))
        { "label" => "See #{other.title}", "path" => path, "by" => who_acts(counted_rows) }.compact
      end

      def progress(counted_rows)
        measures = counted_rows.first&.measures || {}
        measures.slice("confirmed", "owed").then { |pair| pair.size == 2 ? pair : {} }
      end

      # Who acts on the other checklist's counting items that aren't complete,
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
