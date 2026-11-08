# Prepended to ChecklistItemsController from
# config/initializers/checklists.rb: an item can be listed at the kiosk
# while it isn't done (show_on_kiosk, off until an organizer turns it on).
module Checklists::KioskItemParams
  private

  def item_params
    permitted = super
    value = params.dig(:checklist_item, :show_on_kiosk)
    permitted[:show_on_kiosk] = ActiveModel::Type::Boolean.new.cast(value) unless value.nil?
    permitted
  end
end
