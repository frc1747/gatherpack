class PushKeysController < InternalController
  before_action :set_gateway

  # GET /gateways/1/push_keys/edit
  def edit
  end

  # PATCH /gateways/1/push_keys
  def update
    @gateway.replace_keys
    redirect_to gateway_path(@gateway), notice: "Keys replaced.", status: :see_other
  end

  private
    def set_gateway
      @gateway = authorize Gateway::WebPushGateway.find(params[:gateway_id])
    end
end
