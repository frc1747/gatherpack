# Included into Doorkeeper::AuthorizationsController by
# config/initializers/mcp.rb. Applies only to authorization requests that ask
# for an MCP scope; other OAuth clients are unaffected (Doorkeeper's force_pkce
# is global, so it isn't set).
#
# Where the grants table has the PKCE columns, the request must use PKCE with
# S256. Upstream's grants table has no PKCE columns, so public clients can't be
# protected and are refused: only confidential clients get MCP tokens.
module Mcp::RequirePkce
  extend ActiveSupport::Concern

  included do
    before_action :require_mcp_pkce, only: %i[new create]
  end

  private

  def require_mcp_pkce
    return unless params[:scope].to_s.split.intersect?(Mcp::SCOPES)

    reason = Mcp.pkce_supported? ? mcp_pkce_problem : mcp_public_client_problem
    return if reason.nil?

    render_error_response(Doorkeeper::OAuth::InvalidRequestResponse.new(reason: reason, state: params[:state]))
  end

  def mcp_pkce_problem
    :mcp_pkce_required unless params[:code_challenge].present? && params[:code_challenge_method] == "S256"
  end

  # An unknown client is left to Doorkeeper's own error.
  def mcp_public_client_problem
    application = Doorkeeper.config.application_model.by_uid(params[:client_id])
    :mcp_confidential_client_required if application && !application.confidential?
  end
end
