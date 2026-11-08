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
    chosen = Array(params[:topics]).map(&:to_s) & GatherPack::PushTopics.keys.map(&:to_s)
    PushPreference.find_or_create_by!(user: current_user).update!(enabled_topics: chosen)
    redirect_to notifications_path, notice: "Saved.", status: :see_other
  end
end
