module ThemePalette
  # Theme has one site-wide row and only admins may change it. Included into
  # ThemePolicy from config/initializers/theme_palette.rb; edit? follows update?.
  module ThemePolicyRules
    def update?
      user&.admin
    end
  end
end
