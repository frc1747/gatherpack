# Opening a pairing link on a computer, and confirming, makes that browser a
# kiosk device (see KioskDeviceAuthentication). The link's code is the
# credential, so no one has to be signed in and there is nothing for Pundit
# to authorize. Confirming is a separate POST so a link preview or prefetch
# can't use up the code.
class KioskDevicePairingsController < InternalController
  include KioskDeviceAuthentication
  layout "kiosk"
  skip_before_action :check_for_user
  before_action :require_feature
  before_action :set_kiosk_device

  # A kiosk account signed in on the computer can pair it too.
  def kiosk_page?
    true
  end

  # GET /time_kiosk/pair/:code
  def show
  end

  # POST /time_kiosk/pair/:code
  def create
    secret = @kiosk_device.pair!(params[:code])
    return refuse_code unless secret

    remember_kiosk_device(@kiosk_device, secret)
    redirect_to time_kiosk_path, status: :see_other
  end

  private

  def require_feature
    skip_authorization
    head :not_found unless KioskDevice.enabled?
  end

  def set_kiosk_device
    @kiosk_device = KioskDevice.find_by_pairing_code(params[:code])
    refuse_code unless @kiosk_device
  end

  def refuse_code
    render :refused, status: :not_found
  end
end
