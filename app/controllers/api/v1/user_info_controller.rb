class Api::V1::UserInfoController < InternalController
  before_action :doorkeeper_authorize!
  skip_before_action :check_for_user

  # The access token is the authorization: it reads only its own owner's
  # details, limited to the token's scopes.
  def show
    skip_authorization
    user = User.find(doorkeeper_token.resource_owner_id)
    render json: user_info_payload(user)
  end

  private

  def user_info_payload(user)
    payload = { sub: user.neat_id }

    scopes = doorkeeper_token.scopes

    if scopes.exists?(:user_email)
      payload[:email] = user.email
      # Addresses are never confirmed, so none is claimed as verified.
      payload[:email_verified] = false
    end

    if scopes.exists?(:user_name) && user.person
      payload[:name] = user.person.display_name
      payload[:preferred_username] = user.person.display_name
      payload[:given_name] = user.person.first_name
      payload[:family_name] = user.person.last_name
      payload[:profile] = person_url(user.person)
      # Signed for this request and expiring like every file link: clients
      # fetch it when the member signs in, and a link that never expired
      # would outlive the client's access.
      payload[:picture] = url_for(user.person.avatar) if user.person.avatar.attached? && user.person.avatar.variable?
    end

    if scopes.exists?(:teams_read) && user.person
      payload[:teams] = user.person.teams.pluck(:name)
    end

    if scopes.exists?(:badges_read) && user.person && GatherPack::Features.enabled?(:badges)
      payload[:badges] = user.person.badges.pluck(:name)
    end

    if scopes.exists?(:roles_read) && user.person
      payload[:roles] = user.person.roles
    end

    payload
  end
end
