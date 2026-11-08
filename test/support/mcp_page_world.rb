# Pages at each viewer level for MCP tests (call after build_mcp_world). @pages holds them.
module McpPageWorld
  def build_mcp_page_world
    @pages = {
      public: create_page("Public", viewer: "public", editor: "admin"),
      members: create_page("For members", viewer: "user", editor: "admin"),
      alpha_team: create_page("Alpha for team", viewer: "team", editor: "manager", team: @alpha),
      alpha_managers: create_page("Alpha for managers", viewer: "manager", editor: "manager", team: @alpha),
      beta_team: create_page("Beta for team", viewer: "team", editor: "team", team: @beta),
      admin_only: create_page("Admins", viewer: "admin", editor: "admin"),
      dynamic: create_page("Dynamic", viewer: "admin", editor: "admin", dynamic: true, content: "<%= 1 + 1 %>")
    }
  end

  def create_page(title, viewer: "user", editor: "admin", team: nil, dynamic: false, content: nil)
    Page.create!(title: title, viewer: viewer, editor: editor, team: team, dynamic: dynamic, content: content || "the body of #{title}")
  end

  # An open dynamic page with this ERB.
  def erb_page(content, viewer: "user")
    create_page("ERB #{SecureRandom.hex(4)}", viewer: viewer, dynamic: true, content: content)
  end
end
