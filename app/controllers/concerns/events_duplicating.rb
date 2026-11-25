# GET /events/1/duplicate: New Event prefilled from an existing event.
module EventsDuplicating
  extend ActiveSupport::Concern

  included do
    before_action :require_event_duplicate, only: :duplicate
  end

  def duplicate
    original = authorize policy_scope(Event).find(params[:id]), :show?
    @event = Event.new(original.duplicate_attributes)
    authorize @event, :create?
    render :new
  end

  private
    def require_event_duplicate
      redirect_to root_path, notice: "Duplicating events is turned off" unless GatherPack::Features.enabled?(:event_duplicate)
    end
end
