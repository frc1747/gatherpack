# One page as the viewer sees it. Mirrors PagesController#show through set_page (line 53:
# policy_scope(Page), then authorize, which is PagePolicy#show?). A page outside either is
# "Not found". Mcp::PageRender runs the real action as the token's user, so dynamic ERB
# and its own permission logic run as they would in a browser, and it explains what
# differs and how a slow render is stopped.
class Mcp::Tools::GetPage < Mcp::Tool
  tool_name "get_page"
  description "One page you can open, as you'd see it, in plain text with tables as Markdown. Dynamic pages run as you, and may take query string `params`. " \
    "A page you can't open is \"Not found\". Renders over 10 seconds are stopped, and output over 200 KB is cut, with truncated: true."
  scope :read
  feature :pages
  input_schema(
    properties: {
      page_id: { type: "string", description: "The page's ID (pg_)" },
      params: {
        type: "object",
        description: "Query string pairs for a dynamic page, as in the page's URL. Values are strings",
        additionalProperties: { type: "string" }
      }
    },
    required: [ "page_id" ]
  )
  output_schema(
    type: "object",
    properties: {
      id: { type: "string" },
      title: { type: "string" },
      team: { anyOf: [ REF_SCHEMA, { type: "null" } ] },
      dynamic: { type: "boolean" },
      content: { type: "string" },
      truncated: { type: "boolean" }
    },
    required: %w[id title team dynamic content truncated]
  )

  def call(page_id:, params: {})
    page = ctx.find(Page, page_id)
    not_found! unless ctx.allowed?(page, :show?)

    rendered = Mcp::PageRender.new(ctx, page, params).call
    {
      id: page.neat_id,
      title: page.title,
      team: page.team && team_json(page.team),
      dynamic: page.dynamic == true,
      content: rendered.text,
      truncated: rendered.truncated
    }
  end
end
