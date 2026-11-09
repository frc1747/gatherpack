module GatherPack
  # Registry of template override folders. An override is a directory laid out
  # like app/views; while its +active+ check is true for a request, it is
  # searched before the application's own views.
  #
  #   GatherPack::ViewOverrides.register(
  #     :my_skin,
  #     path: Rails.root.join("app/view_overrides/my_skin"),
  #     position: 10,
  #     active: ->(controller) { MySkin.active?(controller) }
  #   )
  #
  # Higher positions are searched first. The check runs on every request,
  # signed-out ones included, so it must not assume a current user.
  module ViewOverrides
    Override = Struct.new(:key, :path, :position, :active, keyword_init: true)

    @overrides = {}

    class << self
      def register(key, path:, position:, active: ->(_controller) { true })
        @overrides[key.to_sym] = Override.new(key: key.to_sym, path: path.to_s, position: position, active: active)
      end

      def unregister(key)
        @overrides.delete(key.to_sym)
      end

      def all
        @overrides.values
      end

      def reset!
        @overrides = {}
      end

      # Paths of the overrides active for this controller, highest position first.
      def active_paths(controller)
        all.select { |override| override.active.call(controller) }
           .sort_by.with_index { |override, index| [ -override.position, -index ] }
           .map(&:path)
      end
    end

    # Added to ApplicationController, which Devise controllers inherit from.
    module Controller
      extend ActiveSupport::Concern

      included do
        prepend_before_action :apply_view_overrides
      end

      private

      def apply_view_overrides
        paths = GatherPack::ViewOverrides.active_paths(self)
        prepend_view_path(paths) if paths.any?
      end
    end
  end
end
