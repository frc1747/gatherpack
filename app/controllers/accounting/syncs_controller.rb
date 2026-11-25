# Sync now and Copy everything again on a source. Admins.
class Accounting::SyncsController < Accounting::BaseController
  before_action :set_source

  # POST /accounting/connections/:id/sync
  def sync
    queue(Accounting::ChangesJob, "Syncing. New and changed records show in a minute or two.")
  end

  # POST /accounting/connections/:id/full_sync
  def full_sync
    queue(Accounting::FullSyncJob, "Copying everything again. This can take a few minutes.")
  end

  private
    def set_source
      @source = find_source(params[:id])
      authorize @source, :sync?, policy_class: Accounting::SourcePolicy
    end

    def queue(job, notice)
      unless @source.syncable?
        return redirect_to accounting_connection_records_path(@source), alert: "#{@source.source_name} isn't connected.", status: :see_other
      end

      job.perform_later(@source)
      redirect_to accounting_connection_records_path(@source), notice: notice, status: :see_other
    end
end
