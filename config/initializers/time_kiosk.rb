# Kiosk accounts are kept to the kiosk (see KioskConfinement) on the pages
# that don't inherit from ApplicationController too:
# - Doorkeeper's pages (approving an app's access): an app authorized from a
#   kiosk would act as the kiosk account.
# - Active Storage's direct-upload endpoint: anyone at a kiosk could store
#   files.
# Active Storage's file links stay open: the kiosk shows people's photos.
Rails.application.config.to_prepare do
  [ Doorkeeper::ApplicationController, ActiveStorage::DirectUploadsController ].each do |controller|
    controller.include(KioskConfinement)
    controller.before_action :confine_kiosk_account
  end
end
