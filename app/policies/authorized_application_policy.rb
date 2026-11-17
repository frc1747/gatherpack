# The OAuth applications a user has authorized, which they may list and
# revoke for themselves. Records are OauthApplications, so callers pass
# policy_class: / policy_scope_class: explicitly.
class AuthorizedApplicationPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    # Applications holding a token or code of the user's that isn't revoked.
    def resolve
      tokens = Doorkeeper.config.access_token_model.where(resource_owner_id: user.id, revoked_at: nil)
      grants = Doorkeeper.config.access_grant_model.where(resource_owner_id: user.id, revoked_at: nil)
      scope.where(id: tokens.select(:application_id)).or(scope.where(id: grants.select(:application_id)))
    end
  end

  def index?
    user.present?
  end

  # Revoking only touches the user's own tokens, but only for an app they
  # have authorized.
  def destroy?
    Scope.new(user, OauthApplication).resolve.exists?(record.id)
  end
end
