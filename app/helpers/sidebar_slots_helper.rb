module SidebarSlotsHelper
  def sidebar_slots
    GatherPack::SidebarSlots.slots_for(self)
  end

  # Puts the registered attributes on an element around the sidebar. It has no
  # box of its own, so the sidebar stays a column of the page's row. With nothing
  # registered the sidebar renders on its own, with no wrapper.
  def sidebar_with_root_attributes(&block)
    attributes = GatherPack::SidebarSlots.attributes_for(self)
    return capture(&block) if attributes.empty?

    tag.div(**attributes, style: "display: contents", &block)
  end
end
