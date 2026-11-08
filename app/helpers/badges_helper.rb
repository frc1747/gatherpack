module BadgesHelper
  def badge_as_badge(badge, **opts)
    link_to badge, class: "undecorated", data: opts[:data] do
      tag.span i(badge.short), class: "badge", style: "background-color: #{safe_color(badge.color)}; color: #{contrasting_color(badge.color)}", title: badge.identifier_name
    end
  end
end
