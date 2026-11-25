# Lets a paired kiosk device (see KioskDevice) run the time kiosk with no one
# signed in. The kiosk_device cookie stands in for a signed-in kiosk account
# on the controllers that include this, and nowhere else: no user session is
# created, so every other page still asks the device to sign in. A signed-in
# user always takes precedence over the device.
module KioskDeviceAuthentication
  extend ActiveSupport::Concern

  COOKIE = :kiosk_device

  included do
    skip_before_action :check_for_user, if: :kiosk_device_session?
    before_action -> { current_kiosk_device.seen! }, if: :kiosk_device_session?
    helper_method :current_kiosk_device
  end

  # The paired device this browser belongs to, if kiosk devices are on.
  def current_kiosk_device
    return @current_kiosk_device if defined?(@current_kiosk_device)

    @current_kiosk_device = (KioskDevice.authenticate(cookies.signed[COOKIE]) if KioskDevice.enabled?)
  end

  private

  def kiosk_device_session?
    current_user.nil? && current_kiosk_device.present?
  end

  # Policies see the device in place of a user (see KioskDevice#kiosk?).
  def pundit_user
    kiosk_device_session? ? current_kiosk_device : super
  end

  def remember_kiosk_device(device, secret)
    cookies.permanent.signed[COOKIE] = { value: "#{device.id}:#{secret}", httponly: true, secure: request.ssl?, same_site: :lax }
  end
end
