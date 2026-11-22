# The link in "Confirm your new email": /join/email?token=... Opening it
# shows a page; submitting it changes the login's email.
class Intake::EmailChangesController < InternalController
  include Intake::PublicPages

  skip_before_action :check_for_user
  before_action :limit_requests
  before_action :set_change

  # GET /join/email?token=...
  def show
    skip_authorization
  end

  # POST /join/email
  def create
    skip_authorization
    Intake::EmailChange.apply!(@token)
    render :done
  end

  private

  def limit_requests
    return unless verification_over_limit?
    flash.now[:alert] = Intake::PublicPages::TRY_AGAIN
    render "intake/verifications/expired", status: :too_many_requests
  end

  def set_change
    @token = params[:token].to_s
    @user, @new_email = Intake::EmailChange.resolve(@token)
    render "intake/verifications/expired", status: :not_found unless @user
  end
end
