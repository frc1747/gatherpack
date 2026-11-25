# Who may change phone notification settings: nobody while the feature is off,
# and nobody impersonating, or an admin's phone would get someone else's reminders.
module PhoneNotificationsAccess
  extend ActiveSupport::Concern

  included do
    before_action :require_phone_notifications
  end

  private
    def require_phone_notifications
      return if GatherPack::PushChannel.available? && current_user == true_user

      if request.format.html?
        redirect_to root_path, notice: "You are not allowed to do that", status: :see_other
      else
        head :forbidden
      end
    end
end
