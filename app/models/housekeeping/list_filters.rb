module Housekeeping
  # Patches to other features' list pages, installed from the initializer so
  # their controllers stay as they are. Each wraps the controller's index and
  # narrows the list it built, only while housekeeping is on.
  module ListFilters
    # Archived records leave the list unless ?archived=1 asks for them.
    def self.hide_archived(controller, ivar, key)
      controller.prepend(Module.new do
        define_method(:index) do
          super()
          type = Housekeeping.type(key)
          return if type.nil? || params[:archived].present?

          instance_variable_set(ivar, type.unarchived(instance_variable_get(ivar)))
        end
      end)
    end

    # ?no_activity[...] (the relative date control) keeps the people with no
    # activity since that date.
    def self.no_activity(controller, ivar)
      controller.prepend(Module.new do
        define_method(:index) do
          super()
          date = Housekeeping.enabled? && Housekeeping::ListFilters.date_from(params[:no_activity])
          instance_variable_set(ivar, Housekeeping.people_without_activity_since(date, scope: instance_variable_get(ivar))) if date
        end
      end)
    end

    # The date a relative date control's params mean today, or nil.
    def self.date_from(value)
      value = value.permit(:mode, :date, :amount, :unit) if value.respond_to?(:permit)
      return unless value.respond_to?(:to_h)

      Checklists::RelativeDate.from_config(value.to_h.stringify_keys)&.resolve(Date.current)
    end

    # Announcement.visible (the dashboard's) leaves archived ones out.
    module VisibleUnarchived
      def visible
        Housekeeping.type(:announcements) ? super.where(archived_at: nil) : super
      end
    end
  end
end
