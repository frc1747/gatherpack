module SmoothPagesHelper
  SIDEBAR_ACTIONS = [
    "turbo:before-render@document->smooth-icons#convert",
    "turbo:before-render@document->smooth-sidebar#beforeRender",
    "turbo:render@document->smooth-sidebar#afterRender",
    "turbo:before-visit@document->smooth-sidebar#closeOffcanvas",
    "turbo:visit@document->smooth-sidebar#closeOffcanvas"
  ].freeze

  def smooth_pages?
    GatherPack::Features.enabled?(:smooth_pages)
  end

  def smooth_refresh?
    content_for?(:smooth_refresh) || GatherPack::SmoothPages.refresh?(smooth_page_name)
  end

  def smooth_no_preview?
    GatherPack::SmoothPages.no_preview?(smooth_page_name)
  end

  def smooth_pages_sidebar_attributes
    return {} unless smooth_pages?

    {
      id: smooth_sidebar_id,
      data: {
        turbo_permanent: true,
        controller: "smooth-icons smooth-sidebar",
        action: SIDEBAR_ACTIONS.join(" ")
      }
    }
  end

  # Turbo only keeps a permanent element when the next page has the same id, so
  # anything that changes what the sidebar shows has to change this id.
  def smooth_sidebar_id
    parts = [ current_user.id, true_user.id, admin?, smooth_nav_fingerprint ]
    "sidebar-#{Digest::SHA256.hexdigest(parts.join("/"))[0, 12]}"
  end

  private

  def smooth_page_name
    "#{controller_path}##{action_name}"
  end

  def smooth_nav_fingerprint
    nav_labels = GatherPack::Features.nav_sections.flat_map { |section, items| [ section, *items.map(&:label) ] }
    people = [ current_user.person, true_user.person ].flat_map { |person| [ person.identifier_name, person.avatar.attachment&.blob_id ] }

    [ *nav_labels, *sidebar_slots.map(&:key), *people ].join("/")
  end
end
