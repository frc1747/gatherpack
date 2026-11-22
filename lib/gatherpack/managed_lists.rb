module GatherPack
  # Managed lists are the small tables of things a group names for itself:
  # types, units, conditions, payment methods. A feature keeps each one in its
  # own table, with a model that includes ManagedList, and registers it here.
  # Registering gives the list an admin screen at /lists/<key>, a button on
  # the Setup page under the setup_section heading, and a form picker
  # (ManagedListsHelper#managed_list_select).
  #
  # Register from the feature's initializer, guarded so the feature still
  # loads in a build without this seam:
  #
  #   Rails.application.config.to_prepare do
  #     GatherPack::ManagedLists.register(
  #       :stock_units,
  #       model: "StockUnit",
  #       label: "Stock Unit",
  #       plural_label: "Stock Units",
  #       setup_section: "Inventory",
  #       description: "The units stock is counted in.",
  #       feature: :inventory,
  #       fields: [ { name: :whole_numbers, label: "Whole numbers only", hint: "Counts can't have fractions." } ]
  #     ) if defined?(GatherPack::ManagedLists)
  #   end
  #
  # Only admins can manage a list unless `policy:` (called with the User)
  # lets others in too. `feature:` hides the screen and its Setup button
  # while that feature is turned off.
  module ManagedLists
    Field = Struct.new(:name, :label, :hint, :as, keyword_init: true)

    class List
      attr_reader :key, :label, :plural_label, :setup_section, :setup_position,
        :description, :fields, :feature

      def initialize(key:, model:, label:, plural_label: nil, setup_section: nil,
        setup_position: 50, description: nil, fields: [], policy: nil, feature: nil)
        @key = key.to_sym
        @model_name = model.is_a?(Class) ? model.name : model.to_s
        @label = label
        @plural_label = plural_label || label.pluralize
        @setup_section = setup_section
        @setup_position = setup_position
        @description = description
        @fields = Array(fields).map { |field| field.is_a?(Field) ? field : Field.new(**field) }
        @policy = policy
        @feature = feature&.to_sym
      end

      # Looked up by name so a development reload picks up the new class.
      def model
        @model_name.constantize
      end

      def model_name
        @model_name
      end

      def available?
        feature.nil? || GatherPack::Features.enabled?(feature)
      end

      def allowed?(user)
        return false unless user
        return true if user.admin

        @policy ? !!@policy.call(user) : false
      end
    end

    # The Setup page lists features by section, so each list adds one that is
    # shown while the list is registered and available.
    class SetupEntry < GatherPack::Feature
      def initialize(list)
        @list_key = list.key
        list_key = list.key
        super(
          key: :"managed_list_#{list.key}",
          label: list.plural_label,
          toggleable: false,
          nav_position: list.setup_position,
          setup_section: list.setup_section,
          setup_items: [
            GatherPack::Feature::SetupItem.new(
              label: list.plural_label,
              path: -> { managed_list_path(list_key) },
              policy_check: ->(view) { ManagedLists.find(list_key)&.allowed?(view.current_user) }
            )
          ]
        )
      end

      def enabled?
        ManagedLists.find(@list_key)&.available? || false
      end
    end

    @lists = {}

    class << self
      def register(key, **options)
        list = List.new(key: key, **options)
        @lists[list.key] = list
        GatherPack::Features.register(SetupEntry.new(list)) if list.setup_section
        list
      end

      def unregister(key)
        @lists.delete(key.to_sym)
      end

      def find(key)
        @lists[key.to_s.to_sym] if key.present?
      end

      def all
        @lists.values
      end

      def for_model(klass)
        @lists.values.find { |list| list.model_name == klass.name }
      end
    end
  end
end
