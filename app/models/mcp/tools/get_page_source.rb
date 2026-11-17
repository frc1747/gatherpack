# A page's stored source, what its edit screen shows. Mirrors PagesController#edit through
# set_page (line 53): policy_scope(Page), then PagePolicy#update? (edit? delegates to it;
# the policy defines it at page_policy.rb line 35), which is the page's editor level. A
# page the viewer can neither edit nor open is "Not found", one they can open but not
# edit "Not allowed". Read only.
class Mcp::Tools::GetPageSource < Mcp::Tool
  tool_name "get_page_source"
  description "A page's stored source (Markdown, or ERB if dynamic), with its title, viewer and editor levels and team, if you can edit it. " \
    "\"Not allowed\" if you can open the page but not edit it, \"Not found\" if you can't open it. Read only: change a page on its edit screen."
  scope :read
  feature :pages
  input_schema(
    properties: { page_id: { type: "string", description: "The page's ID (pg_)" } },
    required: [ "page_id" ]
  )
  output_schema(
    type: "object",
    properties: {
      id: { type: "string" },
      title: { type: "string" },
      viewer: { type: "string" },
      editor: { type: "string" },
      team: { anyOf: [ REF_SCHEMA, { type: "null" } ] },
      dynamic: { type: "boolean" },
      content: { type: "string" }
    },
    required: %w[id title viewer editor team dynamic content]
  )

  def call(page_id:)
    page = ctx.find(Page, page_id)
    unless ctx.allowed?(page, :update?)
      raise Mcp::NotAllowed if ctx.allowed?(page, :show?)

      not_found!
    end

    {
      id: page.neat_id,
      title: page.title,
      viewer: page.viewer,
      editor: page.editor,
      team: page.team && team_json(page.team),
      dynamic: page.dynamic == true,
      content: page.content
    }
  end
end
