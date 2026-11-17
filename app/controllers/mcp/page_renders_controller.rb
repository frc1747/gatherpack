# PagesController#show for get_page. Not routed: Mcp::PageRender dispatches to it
# directly. Everything is inherited (check_for_user, set_page with its policy_scope and
# authorize, the time zone, all helpers), so stored ERB runs in the view context a browser
# gets. Three things differ: the user is the token's, set by Mcp::PageRender in the
# request env where Devise would ask Warden; there's no layout, as the tool returns only
# the page's content; and a refusal from Pundit, in set_page or in the page's own ERB,
# answers 403 rather than redirecting.
class Mcp::PageRendersController < PagesController
  USER_ENV_KEY = "gatherpack.mcp.user".freeze

  layout false

  # The real user, under Pretender's current_user. There's no session, so nothing can
  # impersonate, and current_user is this.
  def true_user
    request.env.fetch(USER_ENV_KEY)
  end

  private

  def pundit_not_authorized
    head :forbidden
  end
end
