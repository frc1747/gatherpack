crumb :orders_requests do
  link "Orders", orders_requests_path
end

crumb :order_request do |order_request|
  link order_request.display_title, orders_request_path(order_request)
  parent :orders_requests
end
