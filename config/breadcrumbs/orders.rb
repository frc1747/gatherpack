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
  link "Orders setup", orders_settings_path
  parent :orders_requests
end

crumb :orders_deliveries do
  link "To receive", orders_deliveries_path
  parent :orders_requests
end

crumb :orders_delivery_new do |order_request, line|
  link "Receive #{line.display_name}", new_orders_request_line_delivery_path(order_request, line)
  parent :order_request, order_request
end

crumb :orders_notice_preference do
  link "Buying notices", edit_orders_notice_preference_path
  parent :orders_requests
end
