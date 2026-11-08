module MyGatherpackHelper
  MY_GATHERPACK_ROW_LIMITS = { coming_up: 5 }.freeze
  MY_GATHERPACK_SHORTCUT_SCHEMES = %w[http https mailto tel].freeze

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

  # Home-page rows in a column across its sections: oldest date first, which
  # puts past-due items on top, then undated ones.
  def my_gatherpack_rows(column)
    @my_gatherpack_rows ||= {}
    @my_gatherpack_rows[column] ||= begin
      rows = MyGatherpack.sections_for(column).select(&:items).flat_map do |section|
        instance_exec(&section.items).map { |item| [ section, item ] }
      end
      sorted = rows.sort_by.with_index { |(_section, item), index| [ item.at ? 0 : 1, item.at&.to_time.to_f, index ] }
      MY_GATHERPACK_ROW_LIMITS[column] ? sorted.first(MY_GATHERPACK_ROW_LIMITS[column]) : sorted
    end
  end

  # What a column's sections without items rendered, leaving out any that were blank.
  def my_gatherpack_blocks(column)
    MyGatherpack.sections_for(column).reject(&:items).map { |section| render(section.partial) }.select { |html| html.to_s.strip.present? }
  end

  def my_gatherpack_greeting
    count = my_gatherpack_rows(:todo).size
    status = count.zero? ? "You're all caught up." : "You have #{pluralize(count, "thing")} to do."
    name = current_user.person.first_name
    name.present? ? "Hi #{name}. #{status}" : status
  end

  def my_gatherpack_clocked_in_status
    return unless GatherPack::Features.enabled?(:time_tracking)

    since = current_user.person.time_clock_punches.still_clocked_in.maximum(:start_time)
    return unless since

    "Clocked in since #{since.strftime(since.to_date == Date.current ? "%-I:%M %p" : "%b %-d, %-I:%M %p")}"
  end

  def my_gatherpack_event_items
    events = policy_scope(Event).where("COALESCE(end_time, start_time) >= ?", Time.current).order(:start_time).limit(MY_GATHERPACK_ROW_LIMITS[:coming_up])
    events.map do |event|
      times = [ event.start_time.strftime("%-I:%M %p"), event.end_time&.strftime(event.end_time.to_date == event.start_time.to_date ? "%-I:%M %p" : "%b %-d, %-I:%M %p") ].compact.join(" – ")
      MyGatherpack::Item.new(title: event.name, detail: [ times, event.location.presence ].compact.join(" · "), at: event.start_time, path: event_path(event))
    end
  end

  # Widget slots belong to a separate feature, so this core can't assume them.
  def my_gatherpack_widget_slot(placement)
    render("widgets/slot", placement: placement) if lookup_context.exists?("widgets/slot", [], true)
  end

  # A shortcut's target and color are free text, and this page writes them into
  # an href and a style attribute. Targets keep working unless a browser would
  # run them or send them to another host: relative paths are fine, and a
  # scheme has to be one of these.
  def my_gatherpack_shortcut_target(shortcut)
    target = shortcut.target.to_s
    # Browsers drop tabs and newlines inside URLs, so "/\t/host" means "//host",
    # ignore leading spaces, and read a backslash as a slash.
    url = target.sub(/\A +/, "")
    return "#" if target.match?(/[[:cntrl:]]/) || url.match?(%r{\A[/\\]{2}})

    scheme = url[/\A([a-z][a-z0-9+.-]*):/i, 1]
    scheme.nil? || MY_GATHERPACK_SHORTCUT_SCHEMES.include?(scheme.downcase) ? target : "#"
  end

  def my_gatherpack_shortcut_style(shortcut)
    color = shortcut.color.to_s
    return unless color.match?(/\A(#\h{3,8}|[a-z]+)\z/i)

    "background-color: #{color}; color: #{contrasting_color(color)}"
  end
end
