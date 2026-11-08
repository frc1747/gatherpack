module Checklists
  module Kinds
    # Holds any of the chosen badges, optionally only badges given within the
    # item's dates.
    class Badge < ItemKind
      class << self
        def label = "Badge"
        def description = "Holds a badge"
        def uses_dates? = true

        def settings
          [
            ItemKind::Setting.new(key: :badge_ids, type: :badges, label: "Badges", hint: "Any of these is enough"),
            ItemKind::Setting.new(key: :within_dates, type: :boolean, label: "Only badges given within the item's dates")
          ]
        end

        def references = { "badge_ids" => "Badge" }

        def invalidations
          [ [ ::BadgeAssignment, ->(assignment) { [ assignment.person_id ] } ] ]
        end

        def problems(item)
          problems = missing_references(item)
          problems << "No badge chosen" if Array(item.config["badge_ids"]).compact_blank.empty?
          problems
        end

        def validate(item)
          item.errors.add(:base, "Choose at least one badge") if Array(item.config["badge_ids"]).compact_blank.empty?
        end

        def describe(item)
          names = referenced_records(item, "badge_ids").map(&:name)
          "Holds #{names.size > 1 ? "any of: " : ""}#{names.to_sentence(two_words_connector: ", ", last_word_connector: ", ")}".strip
        end
      end

      def evaluate(person_ids)
        badges = self.class.referenced_records(item, "badge_ids").index_by(&:id)
        # Only badges given by the as-of moment (the checklist's end, or the "as of" date).
        assignments = ::BadgeAssignment.where(person_id: person_ids, badge_id: badges.keys, created_at: ..window.end_time)
        assignments = assignments.where(created_at: window.start_time..window.end_time) if config["within_dates"]
        held = assignments.pluck(:person_id, :badge_id).group_by(&:first)
        wanted = badges.values.map(&:name).to_sentence(two_words_connector: " or ", last_word_connector: " or ")

        person_ids.index_with do |person_id|
          names = Array(held[person_id]).map { |_, badge_id| badges[badge_id].name }
          if names.any?
            Result.met("Holds #{names.to_sentence}", detail: "Holds #{names.to_sentence}#{badge_notes(names, badges)}")
          else
            Result.not_met("No #{wanted.presence || "badge"}",
              detail: config["within_dates"] ? "No #{wanted} given since #{window.starts_on ? I18n.l(window.starts_on, format: :long) : "the start"}" : "Doesn't hold #{wanted.presence || "the badge"}",
              fix: { "label" => "Ask a leader", "by" => "leader" })
          end
        end
      end

      private

      # A badge's description (a sync date, say) belongs in the detail.
      def badge_notes(names, badges)
        notes = badges.values.select { |badge| names.include?(badge.name) && badge.description.present? }.map(&:description)
        notes.any? ? ". #{notes.join(". ")}" : ""
      end
    end
  end
end
