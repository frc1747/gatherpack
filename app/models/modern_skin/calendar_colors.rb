module ModernSkin
  # Prepended to ApplicationHelper: event text is plain black or white under
  # the skin instead of the old look's greige.
  module CalendarColors
    def event_calendar_colors(event)
      colors = super
      return colors unless ModernSkin.active?(controller)

      colors.merge(text: contrasting_color(colors[:background]))
    end
  end
end
