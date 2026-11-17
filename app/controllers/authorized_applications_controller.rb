# Lets a member see the OAuth applications they have authorized and revoke
# them, which signs the application out of their account.
class AuthorizedApplicationsController < InternalController
  def index
    authorize OauthApplication, policy_class: AuthorizedApplicationPolicy
    @oauth_applications = policy_scope(OauthApplication, policy_scope_class: AuthorizedApplicationPolicy::Scope).order(:name)
  end

  def destroy
    oauth_application = policy_scope(OauthApplication, policy_scope_class: AuthorizedApplicationPolicy::Scope).find(params[:id])
    authorize oauth_application, policy_class: AuthorizedApplicationPolicy

    OauthApplication.revoke_tokens_and_grants_for(oauth_application.id, current_user)
    redirect_to authorized_applications_url, notice: "#{oauth_application.name} can no longer access your account.", status: :see_other
  end
end
