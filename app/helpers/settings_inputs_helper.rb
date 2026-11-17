module SettingsInputsHelper
  # The "Default:" text for a setting: what its picker would show, so a
  # JSON or list default reads as words.
  def setting_default_label(setting)
    SettingInput.for(setting)&.default_label || setting.default_value
  end

  # The name of a picker's field: settings[key][part][...].
  def setting_input_name(input, *parts)
    "settings[#{input.setting_key}]" + parts.map { |part| "[#{part}]" }.join
  end

  def setting_input_id(input, *parts)
    [ "settings", input.setting_key, *parts ].join("_").parameterize(separator: "_")
  end

  # The path of a group's own settings page (Settings.page).
  def setting_page_path(page)
    case page.path
    when Symbol then main_app.public_send(page.path)
    when Proc then page.path.call
    else page.path.to_s
    end
  end
end
