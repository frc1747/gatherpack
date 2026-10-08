module WidgetsHelper
  # The widget's content as HTML: Markdown, or ERB for dynamic widgets. An
  # error shows a short notice (with the message, for admins) instead of
  # breaking the dashboard.
  def render_widget_content(widget)
    if widget.dynamic
      ERB.new(widget.content.to_s).result(binding).html_safe
    else
      md widget.content
    end
  rescue StandardError, SyntaxError => e
    Rails.logger.error("Widget #{widget.neat_id} failed to render: #{e.class}: #{e.message}")
    widget_error(e)
  end

  # Hide the widget when there is nothing to show: ERB that rendered nothing
  # (how a widget hides itself from some people), or a widget with no content
  # and no JavaScript.
  def widget_blank?(widget, html)
    html.to_s.strip.empty? && (widget.dynamic || widget.javascript.blank?)
  end

  # The widget's stylesheet, applied only inside the widget.
  def scoped_widget_stylesheet(widget)
    return if widget.stylesheet.blank?

    css = widget.stylesheet.gsub(%r{</style}i, "<\\/style")
    tag.style("[data-widget=\"#{widget.neat_id}\"] {\n#{css}\n}".html_safe)
  end

  def widget_placement_label(placement)
    { "top" => "Top", "left" => "Left column", "right" => "Right column" }.fetch(placement.to_s, placement.to_s.humanize)
  end

  def widget_viewer_label(viewer)
    { "user" => "Everyone signed in", "team" => "Members of the team", "manager" => "Managers of the team", "admin" => "Admins" }.fetch(viewer.to_s, viewer.to_s.humanize)
  end

  private

  def widget_error(error)
    message = "This widget couldn't be shown."
    return tag.div(message, class: "text-muted") unless current_user&.admin

    tag.div(class: "alert alert-danger") do
      safe_join([ message, tag.pre("#{error.class}: #{error.message}", class: "mb-0 mt-2") ])
    end
  end
end
