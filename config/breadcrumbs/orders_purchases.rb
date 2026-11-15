crumb :orders_purchases do
  link "Vendor orders", orders_purchases_path
end

crumb :orders_to_buy do
  link "To buy", to_buy_orders_purchases_path
end

crumb :orders_new_purchase do
  link "Record purchase"
  parent :orders_to_buy
end

crumb :orders_purchase do |purchase|
  link purchase.vendor_name, orders_purchase_path(purchase)
  parent :orders_purchases
end

crumb :orders_edit_purchase do |purchase|
  link "Edit"
  parent :orders_purchase, purchase
end
