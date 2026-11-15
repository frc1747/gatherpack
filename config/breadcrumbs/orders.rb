crumb :orders_requests do
  link "Orders", orders_requests_path
end

crumb :order_request do |order_request|
  link order_request.display_title, orders_request_path(order_request)
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
