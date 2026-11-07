module Checklists
  # The base of every item kind. A kind is a class with a small fixed form
  # (settings) and a batch evaluate. Subclasses override what they need:
  #
  #   self.label, self.description  # shown in the "Add item" menu
  #   self.settings                 # the form's fields (Setting below)
  #   self.problems(item)           # deleted badge, missing field... shown to organizers
  #   self.references               # { "badge_ids" => "Badge" }: config keys naming records
  #   self.invalidations            # [[Model, ->(record) { person ids or :all }]] (§8.2)
  #   self.next_change_at(item, context)  # next moment the answer can change with no data change
  #   self.measures                 # [Measure]: named numbers
  #   self.describe(item)           # the check in one plain sentence
  #   evaluate(person_ids)          # BATCH: { person_id => Result }
  #   explain(result)               # the sentence stored as detail
  #
  # Evaluation reads data directly, without the viewer's permissions:
  # visibility is applied when results are shown (Checklists::Visibility). A
  # kind never writes, calls the network or depends on the viewer.
  class ItemKind
    # One form field. type is :badges, :teams, :checklist, :number, :date,
    # :relative_date (on or after a date, or within the last N days or
    # months; see Checklists::RelativeDate), :choice, :text or :boolean;
    # options for :choice as [[label, value]].
    Setting = Struct.new(:key, :type, :label, :hint, :options, keyword_init: true)

    # A named number in a result. owner_only measures show only to the
    # person, their guardians and leaders.
    Measure = Struct.new(:key, :label, :type, :owner_only, keyword_init: true)

    class << self
      def label
        name.demodulize.titleize
      end

      def description
        ""
      end

      def settings
        []
      end

      def problems(_item)
        []
      end

      def references
        {}
      end

      def invalidations
        []
      end

      def next_change_at(_item, _context)
        nil
      end

      def measures
        []
      end

      # Whether the item's dates mean anything to this kind.
      def uses_dates?
        false
      end

      # Kinds holding child items (any_of).
      def container?
        false
      end

      # The read level an item of this kind gets when it sets none; nil means
      # the checklist's.
      def default_read_level(_item)
        nil
      end

      def describe(item)
        item.label
      end

      # For pooled kinds: the people, among person_ids, whose results the
      # viewer reaches at the "group" read level (people pooled with them).
      # nil means the kind doesn't pool, and group reads as family.
      def group_reach(_item, _viewer, _person_ids)
        nil
      end

      # Validates the item's config (add errors to item.errors).
      def validate(_item); end

      # The config from form params, keeping only this kind's settings.
      def normalize_config(params)
        params = params.to_h.stringify_keys
        settings.each_with_object({}) do |setting, config|
          key = setting.key.to_s
          next unless params.key?(key)

          config[key] = cast(setting, params[key])
        end
      end

      # The records an item's config names, by config key, missing ones
      # dropped.
      def referenced_records(item, key)
        model = references.fetch(key.to_s).constantize
        model.where(id: Array(item.config[key.to_s]).compact_blank).to_a
      end

      # "Badge 'X' was deleted" lines for references that no longer exist.
      def missing_references(item)
        references.flat_map do |key, model_name|
          ids = Array(item.config[key]).compact_blank
          found = model_name.constantize.where(id: ids).ids
          (ids - found).map { "A #{model_name.underscore.humanize(capitalize: false)} this item uses was deleted" }
        end
      end

      private

      def cast(setting, value)
        case setting.type
        when :badges, :teams then Array(value).compact_blank
        when :number then value.presence && value.to_i
        when :boolean then ActiveModel::Type::Boolean.new.cast(value) || false
        when :date then value.presence && Date.parse(value.to_s).iso8601
        when :relative_date then value.respond_to?(:to_h) ? RelativeDate.cast(value) : nil
        else value.to_s.strip.presence
        end
      rescue Date::Error
        nil
      end
    end

    attr_reader :item, :context

    def initialize(item, context)
      @item = item
      @context = context
    end

    def evaluate(_person_ids)
      raise NotImplementedError
    end

    def explain(result)
      result.detail || result.summary
    end

    def config
      item.config || {}
    end

    def window
      @window ||= context.window_for(item)
    end

    # A :relative_date setting, or nil when it isn't set.
    def relative_date(key)
      RelativeDate.from_config(config[key.to_s])
    end
  end
end
