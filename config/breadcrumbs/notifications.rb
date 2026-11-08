crumb :notifications do
  link "Notifications", notifications_path
end

crumb :"gateway/web_push_gateway" do |gateway|
  link gateway.new_record? ? "New gateway" : [ gateway.identifier_name, gateway_path(gateway) ]
  parent :gateways
end
