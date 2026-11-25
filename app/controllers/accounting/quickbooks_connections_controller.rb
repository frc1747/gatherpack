# Signing GatherPack in to QuickBooks (connect, Intuit's redirect back,
# disconnect). Architects only. The person who clicks Connect signs in to
# Intuit as a QuickBooks user who may authorize apps.
class Accounting::QuickbooksConnectionsController < Accounting::BaseController
  STATE_KEY = :accounting_quickbooks_connect

  # GET /accounting/connections/:id/connect
  def connect
    @gateway = quickbooks_gateway(params[:id])
    authorize @gateway, :connect?, policy_class: Accounting::SourcePolicy

    unless Gateway::QuickbooksGateway.encryption_ready?
      return redirect_to gateway_path(@gateway), alert: "Set the encryption keys before connecting."
    end
    if @gateway.client_id.blank? || @gateway.client_secret.blank?
      return redirect_to edit_gateway_path(@gateway), alert: "Enter the client ID and client secret from the Intuit app first."
    end

    state = SecureRandom.urlsafe_base64(32)
    session[STATE_KEY] = { "state" => state, "gateway_id" => @gateway.id }
    redirect_to @gateway.client.authorize_url(state: state, redirect_uri: accounting_quickbooks_callback_url), allow_other_host: true
  end

  # GET /accounting/quickbooks/callback
  def callback
    pending = session.delete(STATE_KEY) || {}
    @gateway = Gateway::QuickbooksGateway.find_by(id: pending["gateway_id"])
    if @gateway.nil?
      skip_authorization
      return redirect_to gateways_path, alert: "This QuickBooks sign-in wasn't started here or has expired. Click Connect again."
    end
    authorize @gateway, :connect?, policy_class: Accounting::SourcePolicy

    unless params[:state].present? && ActiveSupport::SecurityUtils.secure_compare(pending["state"].to_s, params[:state].to_s)
      return redirect_to gateway_path(@gateway), alert: "This QuickBooks sign-in wasn't started here or has expired. Click Connect again."
    end
    if params[:error].present? || params[:code].blank?
      return redirect_to gateway_path(@gateway), alert: "QuickBooks wasn't connected (#{params[:error].presence || 'no code came back'})."
    end

    realm_id = params[:realmId].to_s
    if realm_id.blank?
      return redirect_to gateway_path(@gateway), alert: "QuickBooks didn't say which company was connected. Click Connect again."
    end
    if @gateway.realm_id.present? && @gateway.realm_id != realm_id
      return redirect_to gateway_path(@gateway), alert: "Those are different books from the ones this gateway copies. To copy them, add another QuickBooks gateway."
    end

    @gateway.client.exchange_code(params[:code], redirect_uri: accounting_quickbooks_callback_url)
    @gateway.record_state!(realm_id: realm_id, connection_status: "connected", last_error: nil)
    record_company_name
    Accounting::FullSyncJob.perform_later(@gateway)
    redirect_to gateway_path(@gateway), notice: "Connected to QuickBooks. Its records are being copied now."
  rescue Accounting::Quickbooks::Client::Error, Accounting::TemporaryFailure => e
    redirect_to gateway_path(@gateway), alert: "QuickBooks wasn't connected: #{e.message}."
  end

  # GET /accounting/connections/:id/disconnect (also Intuit's Disconnect URL)
  def disconnect
    @gateway = quickbooks_gateway(params[:id])
    authorize @gateway, :disconnect?, policy_class: Accounting::SourcePolicy

    had_tokens = @gateway.accounting_credential.present?
    revoked = revoke
    @gateway.accounting_credential&.destroy!
    @gateway.record_state!(connection_status: "disconnected")

    notice = "Disconnected from QuickBooks. The records already copied stay."
    notice += " Intuit couldn't be told, so also remove GatherPack from the apps in QuickBooks." if had_tokens && !revoked
    redirect_to gateway_path(@gateway), notice: notice, status: :see_other
  end

  private
    def quickbooks_gateway(id)
      Gateway::QuickbooksGateway.find(id)
    end

    def revoke
      @gateway.client.revoke!
    rescue Accounting::Quickbooks::Client::Error, Accounting::TemporaryFailure
      false
    end

    def record_company_name
      name = @gateway.client.company_info&.dig("CompanyName")
      @gateway.record_state!(company_name: name) if name.present?
    rescue Accounting::Quickbooks::Client::Error, Accounting::TemporaryFailure, Accounting::ReconnectNeeded
      nil
    end
end
