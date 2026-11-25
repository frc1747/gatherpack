# Update webhook events on a sending gateway's page: subscribes the gateway's
# existing webhook to every event the sent email log reads.
class GatewayWebhookEventsController < InternalController
  before_action :require_email_log
  before_action :set_gateway

  # GET /gateways/1/webhook_events
  def show
  end

  # POST /gateways/1/webhook_events
  def create
    @gateway.update_webhook_events!
    redirect_to gateway_path(@gateway), notice: "Webhook events updated."
  rescue Resend::Error, Postmark::Error => e
    Rails.logger.warn("#{@gateway.class}##{@gateway.id} could not update its webhook events (#{e.class}: #{e.message})")
    redirect_to gateway_path(@gateway), alert: "The sending service refused the change: #{e.message}"
  end

  private
    def require_email_log
      redirect_to root_path, notice: "The sent email log is turned off." unless EmailLog.enabled?
    end

    def set_gateway
      @gateway = authorize policy_scope(Gateway).find(params[:gateway_id]), :update?
      raise ActiveRecord::RecordNotFound unless @gateway.updates_webhook_events?
    end
end
