# For fork/sample_data/features/installable-app.rb (feature/installable-app).
#
# Turns the feature on and gives Northwind a short name for the home screen.
Hbr::SampleData.feature "feature/installable-app" do |s|
  s.enable_feature :installable_app
  s.setting(:pwa_short_name, "Northwind")
end
