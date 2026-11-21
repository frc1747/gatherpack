Rails.application.config.to_prepare do
  Settings.register(
    :print_css,
    :text,
    "Print style",
    Rails.root.join("app/assets/stylesheets/print_default.css").read,
    nil,
    "Styles used when any page is printed. Leave blank to print pages as they look on screen."
  )
end
