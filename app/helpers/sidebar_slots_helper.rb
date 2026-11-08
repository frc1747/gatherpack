module SidebarSlotsHelper
  def sidebar_slots
    GatherPack::SidebarSlots.slots_for(self)
  end

  # Extra attributes for the sidebar's root element, with a leading space, or
  # nothing at all when none are registered.
  def sidebar_root_attributes
    attributes = GatherPack::SidebarSlots.attributes_for(self)
    return if attributes.empty?
    " #{tag.attributes(attributes)}".html_safe
  end
end
