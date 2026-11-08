module MyGatherpackHelper
  def my_gatherpack_menu
    @my_gatherpack_menu ||= MyGatherpack::Menu.new(current_user)
  end

  # Everything in this sidebar that varies by person or site, so a sidebar kept
  # between pages is replaced when any of it changes.
  def my_gatherpack_sidebar_fingerprint
    return unless MyGatherpack.enabled?

    menu = my_gatherpack_menu
    groups = [ menu.top, menu.family, menu.more, menu.manage ].map { |items| items.map(&:label).join(",") }
    [ *groups, site_title, Theme.instance.logo.attachment&.blob_id ].join("/")
  end

  def site_title
    Settings[:title].presence || "GatherPack"
  end

  # safe_join because content_for is already escaped and the settings value isn't.
  def browser_title
    return safe_join([ " ", Settings[:title], " | ", content_for(:title) ]) unless MyGatherpack.enabled?

    page = content_for(:title).presence
    page ? safe_join([ site_title, " | ", page ]) : site_title
  end
end
