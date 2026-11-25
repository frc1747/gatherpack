crumb :"gateway/quickbooks_gateway" do |gateway|
  link gateway.new_record? ? "New gateway" : [ gateway.identifier_name, gateway_path(gateway) ]
  parent :gateways
end

# Records, Customers and Uploads sit under Account Status, where admins
# reach them; architects reach Records from the gateway page too. The
# gateway pages themselves stay under Gateways.
crumb :accounting_records do |source|
  link "#{source.name} records", accounting_connection_records_path(source)
  parent :accounting_rules
end

crumb :accounting_record do |record|
  link record.identifier_name, accounting_connection_record_path(record.gateway, record)
  parent :accounting_records, record.gateway
end

crumb :accounting_customers do |source|
  link "#{source.name} customers", accounting_connection_customers_path(source)
  parent :accounting_rules
end

crumb :accounting_customer do |customer|
  link customer.identifier_name, accounting_connection_customer_path(customer.gateway, customer)
  parent :accounting_customers, customer.gateway
end

crumb :accounting_rules do
  link "Account Status", accounting_rules_path
end

crumb :accounting_rule do |rule|
  link rule.name, accounting_rule_path(rule)
  parent :accounting_rules
end

crumb :new_accounting_rule do
  link "New rule", new_accounting_rule_path
  parent :accounting_rules
end

crumb :edit_accounting_rule do |rule|
  link "Edit", edit_accounting_rule_path(rule)
  parent :accounting_rule, rule
end

crumb :person_accounting do |person|
  link "Account", person_accounting_path(person)
  parent person
end

crumb :person_accounting_statement do |person|
  link "Statement", person_accounting_statement_path(person)
  parent :person_accounting, person
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
