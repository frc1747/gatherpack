module Checklists
  # The base of every item kind. A kind is a class with a small fixed form
  # (settings) and a batch evaluate. Subclasses override what they need:
  #
  #   self.label, self.description  # shown in the "Add item" menu
  #   self.settings                 # the form's fields (Setting below)
  #   self.settings_for(viewer)     # the fields as offered to this author (narrowed choices)
  #   self.form_partial             # a partial for a form section of its own (a table of rows)
  #   self.form_params              # what that section posts under config, as permit arguments
  #   self.normalize_form(params)   # the config the section's params give
  #   self.visible_to?(item, viewer, person)  # a cap on who sees a person's result (default true)
  #   self.authorable_by?(item, author)       # whether this author may set the item up so (default true)
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
    # options for :choice as [[label, value]]. A connector can bring its own
    # type: the item form renders the partial checklist_items/settings/_<type>
    # when there is one, and an unknown type's value is kept as text (or
    # override cast_setting).
    # list: true makes any type a list of values (several forms, several
    # choices); :badges and :teams are always lists.
    Setting = Struct.new(:key, :type, :label, :hint, :options, :list, keyword_init: true) do
      def list?
        list.present? || %i[badges teams].include?(type)
      end
    end

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

      # The settings as the item form offers them to this author (a Person):
      # a kind narrows its choices here (only the fields they may read, say).
      # Defaults to settings. What's saved is still checked by settings and
      # authorable_by?, so narrowing here is about what's offered.
      def settings_for(_viewer)
        settings
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

      # A cap on top of read levels and grants: whether viewer may see
      # person's result on this item at all. Applied to every viewer, admins
      # and organizers included, wherever results show (the report, its sort
      # and filters, status_for, the preview, recorded lists). A kind whose
      # result carries data the viewer may not read (a field value) says no
      # here. The cap carries upward: a group holding a capped item is
      # capped too, and the overall that viewer sees is worked out from the
      # counting items they may see, so neither gives the answer away.
      def visible_to?(_item, _viewer, _person)
        true
      end

      # The batch form of visible_to?: the ids among person_ids whose
      # results viewer may see. Override it to answer in a few queries; the
      # default asks visible_to? per person, and only when a kind overrides
      # it.
      def visible_person_ids(item, viewer, person_ids)
        return person_ids if method(:visible_to?).owner == ItemKind.singleton_class

        people = ::Person.where(id: person_ids).index_by(&:id)
        person_ids.select { |id| people[id] && visible_to?(item, viewer, people[id]) }
      end

      # Whether author (a Person) may set the item up with its config, so
      # nobody builds an item that reads what they couldn't see themselves.
      # Checked when an item is created, edited, previewed or copied.
      def authorable_by?(_item, _author)
        true
      end

      # For pooled kinds: the people, among person_ids, whose results the
      # viewer reaches at the "group" read level (people pooled with them).
      # nil means the kind doesn't pool, and group reads as family.
      def group_reach(_item, _viewer, _person_ids)
        nil
      end

      # Validates the item's config (add errors to item.errors).
      def validate(_item); end

      # A kind whose form needs more than settings (a table of rows, say)
      # names a partial here. It's rendered in the item form after the
      # settings, with locals f (the item form), item, checklist and
      # field_name (the param prefix for its fields, "checklist_item[config]").
      def form_partial
        nil
      end

      # What the form section posts under config, as arguments to permit:
      # [{ rules: [:name, :share] }] for rows of rules.
      def form_params
        []
      end

      # The config the form section's params give (permitted already), kept
      # alongside the settings. Cast and validate here.
      def normalize_form(_params)
        {}
      end

      # The config from form params, keeping only this kind's settings and
      # what its form section gives.
      def normalize_config(params)
        params = params.to_h.stringify_keys
        config = settings.each_with_object({}) do |setting, values|
          key = setting.key.to_s
          next unless params.key?(key)

          values[key] = cast(setting, params[key])
        end
        config.merge(normalize_form(params).to_h.stringify_keys)
      end

      # The arguments to permit the item form's config with: each setting
      # plus the form section's.
      def permitted_config
        keys = settings.map do |setting|
          if setting.list? then { setting.key => [] }
          elsif setting.type == :relative_date then { setting.key => %i[mode date amount unit] }
          else setting.key
          end
        end
        keys + Array(form_params)
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
        return Array(value).compact_blank.filter_map { |one| cast_one(setting, one) } if setting.list?

        cast_one(setting, value)
      end

      def cast_one(setting, value)
        case setting.type
        when :badges, :teams then value.to_s.presence
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
