class SettingsController < InternalController
  before_action :check_for_admin

  # Settings aren't records, so there is nothing to scope; authorize covers
  # the whole page.
  def index
    authorize :settings
    skip_policy_scope
  end

  def update
    authorize :settings
    params[:settings].each do |key, val|
      Settings.set(key.to_sym, val)
    end
    redirect_to settings_path, notice: "Settings were successfully updated.", status: :see_other
  end
end
