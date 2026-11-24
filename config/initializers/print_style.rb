Rails.application.config.to_prepare do
  Settings.register(
    :print_css,
    :text,
    "Print style",
    Rails.root.join("app/assets/stylesheets/print_default.css").read,
    nil,
    "Styles used when any page is printed. Leave blank to print pages as they look on screen."
  )

  # Where settings pickers exist, draw it as a monospace box whose Default line
  # names the standard style instead of printing the whole stylesheet.
  if Settings.respond_to?(:input)
    Settings.input(:print_css, :partial, partial: "print_styles/setting_field", default_label: "The standard print style")
  end
end
