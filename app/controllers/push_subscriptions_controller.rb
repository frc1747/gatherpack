class PushSubscriptionsController < InternalController
  include PhoneNotificationsAccess

  # POST /push_subscription
  # Only this, the explicit toggle, attaches a device. A device held by someone
  # else moves to the person who opted in.
  def create
    subscription = PushSubscription.find_or_initialize_by(endpoint: params.require(:endpoint))
    subscription.assign_attributes(user: current_user, p256dh: params[:p256dh], auth: params[:auth], device_label: device_label)
    authorize subscription

    if subscription.save
      session[:push_subscription_id] = subscription.id
      head :created
    else
      head :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # POST /push_subscription/sync
  # Runs on page load. It never creates a row or moves one to a different user:
  # the browser unsubscribes when told the endpoint isn't this person's.
  def sync
    authorize PushSubscription
    subscription = policy_scope(PushSubscription).find_by(endpoint: params.require(:endpoint))

    if subscription
      subscription.update_column(:device_label, device_label)
      session[:push_subscription_id] = subscription.id
    else
      session.delete(:push_subscription_id)
    end

    render json: { known: subscription.present? }
  end

  # DELETE /push_subscription, with the endpoint (this device) or an id (another one).
  def destroy
    subscriptions = policy_scope(PushSubscription)
    subscription = params[:id].present? ? subscriptions.find(params[:id]) : subscriptions.find_by(endpoint: params.require(:endpoint))

    if subscription
      authorize subscription
      session.delete(:push_subscription_id) if session[:push_subscription_id] == subscription.id
      subscription.destroy!
    else
      skip_authorization
    end

    if request.format.html?
      redirect_to notifications_path, notice: "Device removed.", status: :see_other
    else
      head :no_content
    end
  end

  private
    def device_label
      PushSubscription.device_label(request.user_agent)
    end
end
