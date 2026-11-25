# A kiosk account is signed in on a shared device, so it may only run the
# time kiosk and sign in or out. Anything else sends it back to the kiosk, or is
# refused when the request isn't for a page. Admins flagged as kiosks are
# not kept to it (see User#kiosk_account?).
module KioskConfinement
  extend ActiveSupport::Concern

  included do
    helper_method :kiosk_account?
  end

  # Whether this page is the time kiosk.
  def kiosk_page?
    false
  end

  def kiosk_account?
    current_user.present? && current_user.kiosk_account?
  end

  private

  def confine_kiosk_account
    return unless kiosk_account?
    return if kiosk_page? || signing_in_or_out? || stopping_impersonation?

    if request.format.symbol == :html
      # The app's own route helpers, since an engine (such as /jobs) would
      # put its mount point in front of a path built from the request.
      redirect_to Rails.application.routes.url_helpers.time_kiosk_path, status: :see_other
    else
      head :forbidden
    end
  end

  # Asking for current_user while signing in already signs the user in, so
  # the whole sessions controller is left alone. A kiosk account that opens
  # the sign-in page is sent on to the kiosk from there.
  def signing_in_or_out?
    is_a?(Devise::SessionsController)
  end

  # An admin impersonating a kiosk account can still end the impersonation.
  def stopping_impersonation?
    respond_to?(:true_user, true) && current_user != true_user &&
      controller_path == "people" && action_name == "stop_impersonating"
  end
end
