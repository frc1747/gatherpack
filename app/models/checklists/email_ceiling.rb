module Checklists
  # ItemKind.email_ceiling(item): the most a reminder may say about an item
  # of the kind, from the data it reads (Checklists::EmailLevel). Installed
  # from config/initializers/checklist_reminders.rb, so the kinds themselves
  # don't change:
  #
  #   Checklists::ItemKind.singleton_class.include(Checklists::EmailCeiling)
  #   Checklists::Kinds::PersonField.singleton_class.prepend(Checklists::EmailCeiling::PersonField)
  #
  # A connector whose kind reads data that mustn't travel by email
  # overrides both methods on its kind (or prepends a module the same way).
  module EmailCeiling
    # Everything, unless the kind says otherwise.
    def email_ceiling(_item)
      EmailLevel::LEVELS.first
    end

    # Why, as a clause after "because"; nil when nothing about the data
    # holds it back.
    def email_ceiling_reason(_item)
      nil
    end

    # A profile field kept out of email holds the item at sign_in.
    module PersonField
      def email_ceiling(item)
        kept_out?(item) ? EmailLevel::LEVELS.last : super
      end

      def email_ceiling_reason(item)
        kept_out?(item) ? "it reads #{field(item).name}, which is kept out of email" : super
      end

      private

      def kept_out?(item)
        field = field(item)
        field.respond_to?(:keep_out_of_email?) && field.keep_out_of_email?
      end
    end

    # A group's summary names its items, so it's held at its strictest
    # item's level: what each item's data allows and the level set on the
    # item itself (an item that is a group brings its own items' the same
    # way). Levels the items only inherit, from the checklist or this
    # group, aren't counted here, so the note names the real cause.
    module AnyOf
      def email_ceiling(item)
        EmailLevel.strictest(super, strictest_child(item)&.level)
      end

      def email_ceiling_reason(item)
        child = strictest_child(item)
        return super unless child && EmailLevel.stricter?(child.level, EmailLevel::LEVELS.first)

        "it holds #{child.item.label} (#{EmailLevel.label(child.level).downcase_first})"
      end

      private

      Child = Data.define(:item, :level)

      def strictest_child(item)
        children = item.children.map do |child|
          own = child.email_level if EmailLevel.valid?(child.email_level)
          Child.new(item: child, level: EmailLevel.strictest(EmailLevel.ceiling(child), own))
        end
        children.max_by { |child| EmailLevel::LEVELS.index(child.level) }
      end
    end

    # An item showing another checklist says no more than that checklist's
    # reminders may say about any of its items.
    module ChecklistItem
      def email_ceiling(item)
        EmailLevel.strictest(super, other_level(item))
      end

      def email_ceiling_reason(item)
        other = other_checklist(item)
        return super unless other && EmailLevel.stricter?(other_level(item), EmailLevel::LEVELS.first)

        "it shows #{other.title}, whose reminders say no more"
      end

      private

      def other_checklist(item)
        referenced_records(item, "checklist_id").first
      end

      # Checklists can't require themselves (ChecklistItem#no_cycles); the
      # guard keeps a stored loop from recursing anyway.
      def other_level(item)
        other = other_checklist(item)
        return unless other

        seen = (Thread.current[:checklists_email_ceiling_seen] ||= Set.new)
        return EmailLevel::LEVELS.last if seen.include?(other.id)

        begin
          seen << other.id
          EmailLevel.strictest(EmailLevel.for_checklist(other), other.checklist_items.map { |child| EmailLevel.for(child) })
        ensure
          seen.delete(other.id)
        end
      end
    end
  end
end
