class KioskDevicesController < InternalController
  before_action :require_feature
  before_action :set_kiosk_device, only: %i[ edit update revoke pair ]

  # GET /kiosk_devices
  def index
    authorize KioskDevice
    @kiosk_devices = policy_scope(KioskDevice).order(:name)
  end

  # GET /kiosk_devices/new
  def new
    @kiosk_device = authorize KioskDevice.new
  end

  # GET /kiosk_devices/1/edit
  def edit
  end

  # POST /kiosk_devices
  def create
    @kiosk_device = authorize KioskDevice.new(kiosk_device_params.merge(created_by: current_user))

    if @kiosk_device.save
      show_pairing_link
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /kiosk_devices/1
  def update
    if @kiosk_device.update(kiosk_device_params)
      redirect_to kiosk_devices_path, notice: "Kiosk device was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # PATCH /kiosk_devices/1/revoke
  def revoke
    @kiosk_device.revoke!
    redirect_to kiosk_devices_path, notice: "#{@kiosk_device.name} was revoked. It leaves the kiosk on its next request.", status: :see_other
  end

  # POST /kiosk_devices/1/pair
  def pair
    show_pairing_link
  end

  private
    def require_feature
      redirect_to root_path, notice: "Kiosk devices are turned off" unless KioskDevice.enabled?
    end

    def set_kiosk_device
      @kiosk_device = authorize KioskDevice.find(params[:id])
    end

    # The code is shown once, on this response, and never stored.
    def show_pairing_link
      @pairing_code = @kiosk_device.issue_pairing_code!
      response.headers["Cache-Control"] = "no-store"
      render :pairing_link
    end

    def kiosk_device_params
      params.require(:kiosk_device).permit(:name)
    end
end
