# Sync now and Copy everything again on a source. Sync now: admins,
# architects and customer matchers (from the Customers page); Copy everything
# again: admins and architects.
class Accounting::SyncsController < Accounting::BaseController
  before_action :set_source

  # Where Sync now may send people back to; anything else goes to Records.
  RETURN_TO = { "customers" => :accounting_connection_customers_path }.freeze

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
      authorize @source, (action_name == "full_sync" ? :full_sync? : :sync?), policy_class: Accounting::SourcePolicy
    end

    def queue(job, notice)
      unless @source.syncable?
        return redirect_to return_path, alert: "#{@source.source_name} isn't connected.", status: :see_other
      end

      job.perform_later(@source)
      redirect_to return_path, notice: notice, status: :see_other
    end

    def return_path
      helper = RETURN_TO[params[:from].to_s]
      helper ? send(helper, @source) : accounting_connection_records_path(@source)
    end
end
