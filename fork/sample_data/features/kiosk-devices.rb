# Sample data for feature/kiosk-devices (fork/sample_data/features/kiosk-devices.rb).
#
# Two kiosk devices on Setup → Time → Kiosk Devices: "Front door", paired and
# seen earlier today, and "Shop", revoked. Front door is paired through the
# model's own pairing steps; the browser cookie it would hold is never kept,
# so no computer is actually paired by loading this. Use "Pair again" on the
# list to pair a real browser with it.
Hbr::SampleData.feature "feature/kiosk-devices" do |s|
  s.enable_feature :kiosk_devices
  admin = s.login(:admin).user

  front_door = s.upsert!(KioskDevice, { name: "Front door" }, created_by: admin)
  front_door.pair!(front_door.issue_pairing_code!)
  front_door.update_columns(last_seen_at: s.clock.hours_ago(2))

  shop = s.upsert!(KioskDevice, { name: "Shop" }, created_by: admin)
  shop.pair!(shop.issue_pairing_code!)
  shop.update_columns(last_seen_at: s.clock.days_ago(3, hour: 16))
  shop.revoke!

  s.report "2 kiosk devices: Front door (paired), Shop (revoked)"
  s.expect("Front door is paired") { KioskDevice.find_by!(name: "Front door").paired? }
  s.expect("Shop is revoked") { KioskDevice.find_by!(name: "Shop").revoked? }
end
