module Checklists
  # What a reminder (an email, a phone notification, a summary section) may
  # say about a checklist item:
  #
  #   everything  the item's name, its status and its summary, with a link to fix it
  #   name_only   the item's name and status
  #   sign_in     nothing: it's counted ("1 more item. Sign in to see it.")
  #
  # Three things set it and the strictest wins: the data the item reads
  # (ItemKind.email_ceiling: a profile field kept out of email holds its item
  # at sign_in), the checklist's email_level (the most any item may say) and
  # the item's own (which can only lower it, and lowers the items in a group
  # too). At sign_in on the checklist, a reminder doesn't name the checklist
  # either.
  #
  # Everything that sends a reminder asks EmailLevel.for(item), so the
  # email, the phone notification, the editor's note and the preview can't
  # disagree.
  module EmailLevel
    # Least strict first.
    LEVELS = %w[everything name_only sign_in].freeze

    DEFAULT_LABELS = {
      "everything" => "Everything",
      "name_only" => "Name only",
      "sign_in" => "Just \"sign in\""
    }.freeze

    # The settings holding each level's label (the words are tied to code,
    # their labels aren't).
    LABEL_SETTINGS = LEVELS.index_with { |level| :"checklists_email_level_#{level}_label" }.freeze

    Explanation = Data.define(:level, :reason)

    class << self
      def valid?(level)
        LEVELS.include?(level.to_s)
      end

      def label(level)
        level = level.to_s
        Settings[LABEL_SETTINGS[level]].presence || DEFAULT_LABELS.fetch(level)
      end

      # [[label, level], ...] for a choice.
      def options
        LEVELS.map { |level| [ label(level), level ] }
      end

      def strictest(*levels)
        levels.flatten.compact.map(&:to_s).select { |level| valid?(level) }.max_by { |level| LEVELS.index(level) } || LEVELS.first
      end

      def stricter?(level, than)
        LEVELS.index(level.to_s).to_i > LEVELS.index(than.to_s).to_i
      end

      # The checklist's own level.
      def for_checklist(checklist)
        valid?(checklist.email_level) ? checklist.email_level.to_s : LEVELS.first
      end

      # What a reminder may say about the item: the strictest of its data,
      # its own level and its groups', and the checklist's.
      def for(item)
        explain(item).level
      end

      # The level and why, for the editor's note: the reason is a clause
      # after "because" ("it reads Grade Point Average, which is kept out of
      # email"), or nil at Everything. When two sources agree the data's
      # reason is given, since nothing on the checklist can raise it.
      def explain(item)
        candidates = [ [ ceiling(item), ceiling_reason(item) ] ]
        candidates << [ for_checklist(item.checklist), "the checklist allows no more" ]
        own_levels(item).each { |level, reason| candidates << [ level, reason ] }

        level = strictest(candidates.map(&:first))
        reason = candidates.find { |candidate, _| candidate == level }&.last unless level == LEVELS.first
        Explanation.new(level: level, reason: reason)
      end

      # "Email: just "sign in", because it reads Grade Point Average, which
      # is kept out of email".
      def note(item)
        found = explain(item)
        text = "Email: #{label(found.level).downcase_first}"
        found.reason ? "#{text}, because #{found.reason}" : text
      end

      # What the item's kind allows, from the data it reads. An item whose
      # kind isn't registered is held at the strictest level: nothing can
      # say what it reads.
      def ceiling(item)
        kind = item.kind_class
        return LEVELS.last unless kind

        strictest(kind.email_ceiling(item))
      end

      def ceiling_reason(item)
        kind = item.kind_class
        return "this kind of item isn't available here" unless kind

        kind.email_ceiling_reason(item)
      end

      private

      # The item's own level and those of the groups it's in.
      def own_levels(item)
        levels = []
        current = item
        seen = []
        while current && !seen.include?(current.id)
          seen << current.id
          if valid?(current.email_level)
            levels << [ current.email_level, current.equal?(item) ? "it's set on this item" : "it's set on the group #{current.label}" ]
          end
          current = current.parent
        end
        levels
      end
    end
  end
end
