# For fork/sample_data/features/phone-notifications.rb (feature/phone-notifications).
#
# Turns the feature on, with the gateway set up, and has Ella Brown
# (member@example.com) choose announcements on her phone. There's no
# subscription: those only come from a real device, by turning on "Notify me on
# this phone" at /notifications.
Hbr::SampleData.feature "feature/phone-notifications" do |s|
  s.enable_feature :installable_app
  s.enable_feature :phone_notifications

  gateway = s.upsert!(Gateway::WebPushGateway, { name: "Phones" }, contact: "admin@example.com")
  gateway.finish_setup

  s.upsert!(PushPreference, { user: User.find_by!(email: "member@example.com") }, enabled_topics: %w[announcements])
end
