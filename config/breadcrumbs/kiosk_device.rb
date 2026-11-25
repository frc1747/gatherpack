crumb :kiosk_devices do
  link "Kiosk Devices", kiosk_devices_path
  parent :setup
end

crumb :kiosk_device do |kiosk_device|
  if kiosk_device.new_record?
    link "New kiosk device", new_kiosk_device_path
  else
    link kiosk_device.identifier_name, edit_kiosk_device_path(kiosk_device)
  end
  parent :kiosk_devices
end
