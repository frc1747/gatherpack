module Checklists
  module Kinds
    # Holds child items; met when any child is met, else pending when any is
    # pending, else not met. Children can be groups too, to any depth.
    class AnyOf < ItemKind
      class << self
        def label = "Any one of these"
        def description = "A group where one item is enough"
        def container? = true
        def describe(item) = "Any one of these is enough#{": #{item.children.map(&:label).to_sentence(two_words_connector: ", ", last_word_connector: ", ")}" if item.children.any?}"

        def problems(item)
          item.children.empty? ? [ "The group has no items yet" ] : []
        end
      end

      def evaluate(person_ids)
        children = item.children.to_a
        results = context.evaluate_items(children, person_ids)

        person_ids.index_with do |person_id|
          child_results = children.map { |child| [ child, results.dig(child.id, person_id) ] }
          counted = child_results.reject { |_, result| result.nil? || result.exempt? }
          passed = counted.select { |_, result| result.met? }

          if child_results.any? && counted.empty?
            Result.exempt(item.exempt_label.presence || "Doesn't apply")
          elsif passed.any?
            Result.met("#{passed.map { |child, _| child.label }.to_sentence} done")
          elsif counted.any? { |_, result| result.pending? }
            Result.pending("Almost: #{counted.select { |_, result| result.pending? }.map { |child, _| child.label }.to_sentence}")
          else
            Result.not_met("None done yet", detail: "Any one of these is enough: #{children.map(&:label).to_sentence}",
              fix: fix_for(counted))
          end
        end
      end

      private

      # The fix of the first child the person (or a guardian) can act on, or
      # else the first child's: any one is enough, so one they can do alone
      # beats asking a leader. It keeps its "by", and carries the child's
      # item_id, which a confirm button needs (the group isn't the item
      # confirmed).
      def fix_for(counted)
        fixes = counted.filter_map { |child, result| result.fix&.reverse_merge("item_id" => child.id) }
        fixes.find { |fix| fix["by"].present? && fix["by"] != "leader" } || fixes.first
      end
    end
  end
end
