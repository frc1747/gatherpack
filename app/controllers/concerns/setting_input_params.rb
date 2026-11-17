# Added to SettingsController (config/initializers/settings_inputs.rb):
# - drops blank values of the settings named in keep_if_blank (fields that
#   don't show the saved value, see settings/inputs/_field), so they keep it;
# - turns what each picker posts (see SettingInput) back into the setting's
#   text before the settings are saved, so the save itself is unchanged;
# - after saving, returns to return_to when it is a path on this site, so a
#   feature's own settings page (settings/_form) comes back to itself.
module SettingInputParams
  extend ActiveSupport::Concern

  included do
    before_action :convert_setting_inputs, only: :update
    after_action :redirect_to_return_path, only: :update
  end

  # A path on this site ("/teams/setup"), or nil for anything else: other
  # hosts, protocol-relative "//host" and backslash tricks included.
  def self.local_path(path)
    path = path.to_s
    return unless path.start_with?("/") && !path.start_with?("//") && !path.match?(/[\\\s]/)

    uri = URI.parse(path)
    path if uri.scheme.nil? && uri.host.nil?
  rescue URI::InvalidURIError
    nil
  end

  private

  def convert_setting_inputs
    settings = params[:settings]
    return unless settings.respond_to?(:each_pair)

    Array(params[:keep_if_blank]).each do |key|
      settings.delete(key) if settings.key?(key) && settings[key].blank?
    end

    settings.each_pair do |key, posted|
      input = SettingInput.for(key)
      next unless input

      settings[key] = input.text_from(posted)
    end
  end

  def redirect_to_return_path
    path = SettingInputParams.local_path(params[:return_to])
    response.location = path if path && response.redirect?
  end
end
