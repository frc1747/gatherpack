class NotificationSettingsController < InternalController
  include PhoneNotificationsAccess

  before_action { authorize PushSubscription, :settings? }

  # GET /notifications
  def show
    @gateway = GatherPack::PushChannel.gateway
    @topics = GatherPack::PushTopics.all
    @enabled_topics = current_user.enabled_push_topics
    @other_devices = policy_scope(PushSubscription).where.not(id: session[:push_subscription_id]).order(:created_at)
  end

  # PATCH /notifications
  def update
    offered = GatherPack::PushTopics.keys.map(&:to_s)
    # Topics whose feature is off aren't on the page, so saving keeps what was stored for them.
    kept = Array(current_user.push_preference&.enabled_topics).map(&:to_s) - offered
    chosen = (Array(params[:topics]).map(&:to_s) & offered) | kept
    PushPreference.find_or_create_by!(user: current_user).update!(enabled_topics: chosen)
    redirect_to notifications_path, notice: "Saved.", status: :see_other
  end

  # POST /notifications/test
  def send_test
    sent = GatherPack::PushChannel.deliver_test(current_user, path: notifications_path)

    if sent.zero?
      redirect_to notifications_path, alert: "Turn on notifications on a device first.", status: :see_other
    else
      redirect_to notifications_path, notice: "Test sent to #{helpers.pluralize(sent, "device")}. It should arrive within a minute.", status: :see_other
    end
  end
end
