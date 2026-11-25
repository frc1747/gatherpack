class NotificationSettingsController < InternalController
  include PhoneNotificationsAccess

  # The page also holds other features' cards (GatherPack::NotificationSections),
  # so it opens while one of them is shown even without phone notifications.
  skip_before_action :require_phone_notifications, only: :show
  before_action :require_notifications_page, only: :show
  before_action { authorize PushSubscription, :settings? }

  # GET /notifications
  def show
    @phone = GatherPack::PushChannel.available?
    @sections = GatherPack::NotificationSections.visible_for(current_user)
    return unless @phone

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

  # POST /notifications/test
  def send_test
    sent = GatherPack::PushChannel.deliver_test(current_user, path: notifications_path)

    if sent.zero?
      redirect_to notifications_path, alert: "Turn on notifications on a device first.", status: :see_other
    else
      redirect_to notifications_path, notice: "Test sent to #{helpers.pluralize(sent, "device")}. It should arrive within a minute.", status: :see_other
    end
  end

  private
    def require_notifications_page
      return if current_user == true_user && GatherPack::NotificationSections.page_for?(current_user)

      redirect_to root_path, notice: "You are not allowed to do that", status: :see_other
    end
end
