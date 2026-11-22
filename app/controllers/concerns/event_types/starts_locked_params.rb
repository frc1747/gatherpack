# Lets the event type form save "New events start locked" while the feature
# is on.
module EventTypes::StartsLockedParams
  private

  def event_type_params
    return super unless EventTypes::StartsLocked.enabled?

    super.merge(params.require(:event_type).permit(:starts_locked))
  end
end
