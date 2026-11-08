module GatherPack
  # Lets a feature add a control to the sidebar, or attributes to its root
  # element, without editing the sidebar template. With nothing registered the
  # sidebar renders exactly as it does without this registry.
  module SidebarSlots
    Slot = Struct.new(:key, :partial, :position, :visible, keyword_init: true)
    RootAttributes = Struct.new(:key, :block, keyword_init: true)

    # Module-level storage — loaded once via require_relative, not Zeitwerk-managed
    @slots = {}
    @root_attributes = {}

    class << self
      # Registering the same key again replaces it, so reloading code is safe.
      def register(key, partial:, position: 100, visible: nil)
        @slots[key] = Slot.new(key: key, partial: partial, position: position, visible: visible)
      end

      def root_attributes(key, &block)
        raise ArgumentError, "root_attributes needs a block" unless block
        @root_attributes[key] = RootAttributes.new(key: key, block: block)
      end

      # Slots whose `visible` lambda (run in the view context) allows them,
      # in position order, then registration order.
      def slots_for(view)
        @slots.values
          .each_with_index
          .sort_by { |slot, index| [ slot.position, index ] }
          .map(&:first)
          .select { |slot| slot.visible.nil? || view.instance_exec(view, &slot.visible) }
      end

      # Attributes from every registration, merged in registration order.
      # Nested hashes (data, aria) merge; `class` is dropped so the sidebar
      # keeps its own.
      def attributes_for(view)
        @root_attributes.values.each_with_object({}) do |registration, merged|
          attributes = view.instance_exec(view, &registration.block) || {}
          merged.deep_merge!(attributes.deep_symbolize_keys.except(:class))
        end
      end

      def reset!
        @slots = {}
        @root_attributes = {}
      end
    end
  end
end
