crumb :orders_requests do
  link "Orders", orders_requests_path
end

crumb :order_request do |order_request|
  link order_request.display_title, orders_request_path(order_request)
  parent :orders_requests
end

crumb :orders_vendors do
  link "Vendors", orders_vendors_path
  parent :orders_requests
end

crumb :orders_vendor do |vendor|
  link vendor.name, orders_vendor_path(vendor)
  parent :orders_vendors
end

crumb :orders_funding_sources do
  link "Funding sources", orders_funding_sources_path
  parent :orders_requests
end

crumb :orders_funding_source do |source|
  link source.name, orders_funding_source_path(source)
  parent :orders_funding_sources
end

crumb :orders_reports do
  link "Reports", orders_reports_path
  parent :orders_requests
end

crumb :orders_report do |report|
  link report.title, orders_report_path(report.key)
  parent :orders_reports
end

crumb :orders_settings do
  link "Orders settings", orders_settings_path
  parent :orders_requests
end
