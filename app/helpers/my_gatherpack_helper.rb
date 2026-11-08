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

  PhoneTab = Struct.new(:label, :path, :icon, keyword_init: true)

  # The phone tab bar's links, in order. A tab drops out when its feature is
  # off, since it comes from the same menu as the sidebar. A guardian gets
  # Family first in place of Hours. More isn't here: it opens the sidebar.
  PHONE_TABS = { root_path: "Home", forms_path: "Forms", signup_sheets_path: "Sign-ups", time_clock_punches_path: "Hours" }.freeze

  def my_gatherpack_phone_tabs
    menu = my_gatherpack_menu
    # The menu swaps Hours' path for a proc, so it's keyed by that.
    items = menu.top.index_by { |item| item.path == MyGatherpack::Menu::MY_HOURS_PATH ? :time_clock_punches_path : item.path }
    family = menu.family.find { |item| item.path == :family_path } if phone_family_tab?
    tabs = PHONE_TABS.filter_map do |path, label|
      next if family && path == :time_clock_punches_path

      item = items[path] || next
      PhoneTab.new(label: label, path: resolve_nav_path(item), icon: item.icon)
    end
    tabs.unshift(PhoneTab.new(label: "Family", path: resolve_nav_path(family), icon: family.icon)) if family
    tabs
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

  private

  # The family route and Person#wards come from other branches.
  def phone_family_tab?
    respond_to?(:family_path) && current_user.person.respond_to?(:wards) && current_user.person.wards.any?
  end
end
