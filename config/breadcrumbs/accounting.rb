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

# Under Setup, not the gateway page: the page is for admins, and the
# gateway page is for architects.
crumb :accounting_customers do |source|
  link "#{source.name} customers", accounting_connection_customers_path(source)
  parent :setup
end

crumb :accounting_customer do |customer|
  link customer.identifier_name, accounting_connection_customer_path(customer.gateway, customer)
  parent :accounting_customers, customer.gateway
end

crumb :"gateway/ledger_source" do |gateway|
  if gateway.new_record?
    link "New gateway"
  else
    link gateway.identifier_name, gateway_path(gateway)
  end
  parent :gateways
end

crumb :"gateway/file_source" do |gateway|
  if gateway.new_record?
    link "New gateway"
  else
    link gateway.identifier_name, gateway_path(gateway)
  end
  parent :gateways
end

crumb :new_accounting_upload do |source|
  link "Upload", new_accounting_connection_upload_path(source)
  parent :accounting_records, source
end

crumb :accounting_upload do |upload|
  link upload.identifier_name, accounting_connection_upload_path(upload.gateway, upload)
  parent :accounting_records, upload.gateway
end
