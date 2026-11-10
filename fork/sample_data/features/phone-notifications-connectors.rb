# For fork/sample_data/features/phone-notifications-connectors.rb
# (feature/phone-notifications-connectors).
#
# Has Ella Brown (member@example.com) choose every topic on her phone. Devices
# only come from a real phone, by turning on "Notify me on this phone" at
# /notifications. Runs after feature/phone-notifications, which sets up the gateway.
Hbr::SampleData.feature "feature/phone-notifications-connectors" do |s|
  s.enable_feature :installable_app
  s.enable_feature :phone_notifications

  s.upsert!(PushPreference, { user: User.find_by!(email: "member@example.com") }, enabled_topics: %w[announcements forms shifts commitments])
end
