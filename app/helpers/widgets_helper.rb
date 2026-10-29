module WidgetsHelper
  # Keeps the HTML an admin writes in a Markdown widget (layout, classes and
  # data attributes for the widget's JavaScript) but not scripts, event
  # handlers or unsafe links. The attributes that wire up Stimulus or Turbo
  # are dropped too, so only architects can make a widget run code.
  class MarkdownScrubber < Rails::HTML::PermitScrubber
    BEHAVIOR_ATTRIBUTES = /\Adata-(controller|action|method|remote|turbo)/

    def initialize
      super
      sanitizer = Rails::HTML::Sanitizer.best_supported_vendor.safe_list_sanitizer
      self.tags = sanitizer.allowed_tags
      self.attributes = sanitizer.allowed_attributes
    end

    def scrub_attribute?(name)
      return name.match?(BEHAVIOR_ATTRIBUTES) if name.start_with?("data-")

      super
    end
  end

  # The widget's content as HTML: Markdown, or ERB for dynamic widgets. An
  # error shows a short notice (with the message, for admins) instead of
  # breaking the dashboard.
  def render_widget_content(widget)
    if widget.dynamic
      ERB.new(widget.content.to_s).result(binding).html_safe
    else
      widget_markdown(widget.content)
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

  # Not ApplicationHelper#md, which drops raw HTML: widgets are written by
  # admins, and a widget such as a countdown is HTML for its JavaScript.
  def widget_markdown(content)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML, autolink: true, no_intra_emphasis: true, fenced_code_blocks: true, lax_spacing: true)
    sanitize(markdown.render(content.to_s), scrubber: MarkdownScrubber.new)
  end

  def widget_error(error)
    message = "This widget couldn't be shown."
    return tag.div(message, class: "text-muted") unless current_user&.admin

    tag.div(class: "alert alert-danger") do
      safe_join([ message, tag.pre("#{error.class}: #{error.message}", class: "mb-0 mt-2") ])
    end
  end
end
