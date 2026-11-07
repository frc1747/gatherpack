module Checklists
  # The base of every item kind. A kind is a class with a small fixed form
  # (settings) and a batch evaluate. Subclasses override what they need:
  #
  #   self.label, self.description  # shown in the "Add item" menu
  #   self.settings                 # the form's fields (Setting below)
  #   self.settings_for(author, item)  # the fields as offered to this author (narrowed choices)
  #   self.copy_dates(item)         # fixed dates in its config that "Copy checklist" shifts
  #   self.apply_copy_dates(item, config, dates)  # the copied config with the new dates in place
  #   self.form_partial             # a partial for a form section of its own (a table of rows)
  #   self.form_params              # what that section posts under config, as permit arguments
  #   self.normalize_form(params)   # the config the section's params give
  #   self.visible_to?(item, viewer, person)  # a cap on who sees a person's result (default true)
  #   self.authorable_by?(item, author)       # whether this author may set the item up so (default true)
  #   self.grantable_by?(item, person, access)  # whether person may grant access to it (default true; enforced on read)
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
    # list: true makes a setting a list of values (several forms, several
    # choices): :choice, :checklist, :number, :date, :text and connectors' own
    # types can be lists, and the item form draws one field per value;
    # :boolean and :relative_date can't (registering such a kind fails).
    # :badges and :teams are always lists.
    #
    # options may be a lambda, called each time they are read, for choices
    # that come from the database: a kind registers (and so reads its
    # settings) during app boot, before the tables may exist on a fresh DB.
    Setting = Struct.new(:key, :type, :label, :hint, :options, :list, keyword_init: true) do
      def options
        value = self[:options]
        value.respond_to?(:call) ? value.call : value
      end

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

      # The fixed dates in an item's config that copying a checklist shifts,
      # as [{ key:, label:, value: }]. key is the kind's own name for each
      # date (a setting key, or a path into its rows such as "rules.0.from");
      # copying hands the keys back to apply_copy_dates. Defaults to the
      # :date settings and the :relative_date ones set to "on or after"; a
      # "within the last N" stays as it is.
      def copy_dates(item)
        settings.select { |setting| %i[date relative_date].include?(setting.type) && !setting.list? }.filter_map do |setting|
          value = item.config[setting.key.to_s]
          date = value.is_a?(Hash) ? RelativeDate.from_config(value)&.date : (Date.iso8601(value) if value.present?)
          { key: setting.key.to_s, label: setting.label, value: date } if date
        rescue Date::Error
          nil
        end
      end

      # The copied config with the dates confirmed for the copy ({ key =>
      # Date }, keys from copy_dates) in place.
      def apply_copy_dates(_item, config, dates)
        dates.each do |key, date|
          config[key] = config[key].is_a?(Hash) ? RelativeDate.new(date: date).to_config : date.iso8601
        end
        config
      end

      # The settings as the item form offers them to this author (a Person)
      # for this item: a kind narrows its choices here (only the fields they
      # may read, say). Defaults to settings. What's saved is still checked by
      # settings and authorable_by?, so narrowing here is about what's
      # offered. (A one-argument settings_for(author) still works.)
      def settings_for(_author, _item = nil)
        settings
      end

      # settings_for, with the item's saved values kept among each choice's
      # options, so opening an item to rename it never quietly picks
      # something else. What the form draws.
      def offered_settings(author, item)
        offered = method(:settings_for).arity == 1 ? settings_for(author) : settings_for(author, item)
        full = settings.index_by(&:key)
        offered.map do |setting|
          next setting unless setting.type == :choice && setting.options

          saved = Array(item.config[setting.key.to_s]).compact_blank
          missing = saved - setting.options.map { |_, value| value.to_s }
          next setting if missing.empty?

          known = Array(full[setting.key]&.options).to_h { |label, value| [ value.to_s, label ] }
          setting.dup.tap { |kept| kept.options = setting.options + missing.map { |value| [ known[value] || value, value ] } }
        end
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
      #
      # Answer true (or :full) to show the result as usual, :status to show
      # only its status (Done, Not yet, a label such as "Excused") with no
      # summary, detail, measures or fix, or false to hide it.
      def visible_to?(_item, _viewer, _person)
        true
      end

      # The batch form of the cap: { person_id => :full or :status } for the
      # people among person_ids whose result viewer may see (at most at that
      # level); the rest are hidden. Override it to answer in a few queries.
      # The default asks visible_to? per person when a kind overrides that,
      # else takes visible_person_ids at :full.
      def cap_levels(item, viewer, person_ids)
        if overrides?(:visible_to?)
          people = ::Person.where(id: person_ids).index_by(&:id)
          person_ids.each_with_object({}) do |id, levels|
            level = people[id] && cap_level(visible_to?(item, viewer, people[id]))
            levels[id] = level if level
          end
        elsif overrides?(:visible_person_ids)
          visible_person_ids(item, viewer, person_ids).index_with(:full)
        else
          person_ids.index_with(:full)
        end
      end

      # The ids among person_ids whose result viewer may see at all (at
      # either level). Overriding it caps at :full or hidden; override
      # cap_levels instead for status-only answers.
      def visible_person_ids(item, viewer, person_ids)
        return cap_levels(item, viewer, person_ids).keys if overrides?(:cap_levels) || overrides?(:visible_to?)

        person_ids
      end

      # Whether author (a Person) may set the item up with its config, so
      # nobody builds an item that reads what they couldn't see themselves.
      # Checked when an item is created, edited, previewed or copied.
      def authorable_by?(_item, _author)
        true
      end

      # Whether person may make a grant (ChecklistGrant) showing this item at
      # access (:status or :full). Core enforces it everywhere: making a grant
      # or copying a checklist is refused when it says no, and when results
      # are read a grant counts for the item only while its maker still
      # passes (honours_grant?), so adding or moving the item under a granted
      # group, or a copy, can't get around it.
      def grantable_by?(_item, _person, _access)
        true
      end

      # Whether grant shows this item (Checklists::Visibility asks for each
      # item a grant covers). A kind that doesn't override grantable_by?
      # honours every grant. One that does honours a grant only while its
      # maker passes grantable_by?; a grant with no recorded maker (made
      # before makers were kept, or whose maker was deleted) isn't honoured.
      def honours_grant?(item, grant)
        return true if method(:grantable_by?).owner == ItemKind.singleton_class

        grant.created_by.present? && grantable_by?(item, grant.created_by, grant.access.to_sym)
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

      def overrides?(name)
        method(name).owner != ItemKind.singleton_class
      end

      def cap_level(answer)
        case answer
        when :status then :status
        when true, :full then :full
        end
      end

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
