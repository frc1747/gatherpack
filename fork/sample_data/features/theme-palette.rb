# Turns the palette on with a Northwind brand color. Needs the skin, which
# keeps its own flag off; turn on Modern Skin in Setup to see the colors.
Hbr::SampleData.feature "feature/theme-palette" do |s|
  s.enable_feature :theme_palette
  Theme.instance.update!(brand_color: "#1f6f8b")
  s.note "Set the Modern Skin flag to see Northwind's colors; Theme > Edit has the Colors section"
end
