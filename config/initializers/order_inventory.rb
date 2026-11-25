# Order receiving into inventory (orders spec §5): registers into the seams
# of orders and inventory (OrderInventory.register!). Each piece shows and
# acts only while both features are on (OrderInventory.enabled?). Uses
# config.to_prepare (like features.rb) so the registrations are replayed
# after each development reload.
Rails.application.config.to_prepare do
  OrderInventory.register!
end
