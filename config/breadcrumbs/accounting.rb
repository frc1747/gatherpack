crumb :"gateway/quickbooks_gateway" do |gateway|
  link gateway.new_record? ? "New gateway" : [ gateway.identifier_name, gateway_path(gateway) ]
  parent :gateways
end

crumb :accounting_records do |source|
  link "Records", accounting_connection_records_path(source)
  parent :"gateway/quickbooks_gateway", source
end

crumb :accounting_record do |record|
  link record.identifier_name, accounting_connection_record_path(record.gateway, record)
  parent :accounting_records, record.gateway
end
