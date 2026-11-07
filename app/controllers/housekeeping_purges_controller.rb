# A retention purge (Housekeeping.register_purge): admins see exactly what
# would go, as of the age in its setting, and confirm. Each run leaves an
# audit entry.
class HousekeepingPurgesController < InternalController
  include HousekeepingFeature

  before_action :set_purge

  # GET /housekeeping/purges/:key
  def show
    authorize :housekeeping, :purge?
    @cutoff = @purge.default_cutoff
    return unless @cutoff

    records = @purge.records(@cutoff)
    @count = records.count
    @rows = @purge.describe(records.limit(500))
    @last = HousekeepingPurge.where(key: @purge.key).order(created_at: :desc).first
  end

  # POST /housekeeping/purges/:key
  def create
    authorize :housekeeping, :purge?
    @cutoff = @purge.default_cutoff
    return redirect_to(housekeeping_purge_path(@purge.key), alert: "This is turned off in settings.", status: :see_other) unless @cutoff
    # What the person saw must still be what goes.
    if params[:confirmed] != "1" || params[:count].to_i != @purge.records(@cutoff).count
      return redirect_to(housekeeping_purge_path(@purge.key), alert: "Check the list again and tick the box to confirm.", status: :see_other)
    end

    log = @purge.run!(cutoff: @cutoff, by: current_user.person)
    redirect_to housekeeping_purge_path(@purge.key), notice: "Cleared #{log.count}.", status: :see_other
  end

  private

  def set_purge
    @purge = Housekeeping.purge(params[:key])
    raise ActiveRecord::RecordNotFound, "No purge #{params[:key]}" if @purge.nil?
  end
end
