# Included into Doorkeeper::AuthorizationsController by
# config/initializers/mcp.rb. Applies only to authorization requests that ask
# for an MCP scope; other OAuth clients are unaffected (Doorkeeper's force_pkce
# is global, so it isn't set).
#
# The feature must be on and the application's own scopes must list every MCP
# scope requested. Doorkeeper alone would accept any server scope for an
# application with blank scopes. Where the grants table has the PKCE columns,
# the request must use PKCE with S256. Upstream's grants table has no PKCE
# columns, so public clients can't be protected and are refused: only
# confidential clients get MCP tokens.
module Mcp::AuthorizationChecks
  extend ActiveSupport::Concern

  included do
    before_action :check_mcp_authorization, only: %i[new create]
  end

  private

  def check_mcp_authorization
    requested = params[:scope].to_s.split & Mcp::SCOPES
    return if requested.empty?

    # An unknown client is left to Doorkeeper's own error.
    application = Doorkeeper.config.application_model.by_uid(params[:client_id])
    return if application.nil?

    unless Mcp::Access.enabled? && requested.all? { |scope| application.scopes.exists?(scope) }
      return render_error_response(Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_scope, state: params[:state]))
    end

    reason = Mcp.pkce_supported? ? mcp_pkce_problem : mcp_public_client_problem(application)
    render_error_response(Doorkeeper::OAuth::InvalidRequestResponse.new(reason: reason, state: params[:state])) if reason
  end

  def mcp_pkce_problem
    :mcp_pkce_required unless params[:code_challenge].present? && params[:code_challenge_method] == "S256"
  end

  def mcp_public_client_problem(application)
    :mcp_confidential_client_required unless application.confidential?
  end
end
