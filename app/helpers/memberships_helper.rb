module MembershipsHelper
  def membership_as_badge(membership, **opts)
    content = i(membership.manager ? "user-tie" : "user") + " " + membership.team.name
    link_to [ membership.team, membership ] do
      tag.span content, class: "badge", style: "background-color: #{membership.team.color}; color: #{contrasting_color(membership.team.color)}"
    end
  end

  # The team member grid is narrower when the add panel sits beside it.
  def member_grid_col_class(with_add_panel)
    with_add_panel ? "col-6 col-md-4 col-xl-3" : "col-6 col-md-2"
  end
end
