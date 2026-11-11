class OauthApplicationsController < InternalController
  before_action :set_oauth_application, only: %i[show edit update destroy regenerate_secret]

  def index
    authorize OauthApplication
    @q = policy_scope(OauthApplication).ransack(params[:q])
    @oauth_applications = @q.result(distinct: true).page(params[:page])
  end

  def show
  end

  def new
    @oauth_application = authorize OauthApplication.new
  end

  def edit
  end

  def create
    @oauth_application = authorize OauthApplication.new(oauth_application_params)

    if @oauth_application.save
      redirect_to @oauth_application, notice: "OAuth application was successfully created.",
        flash: { client_secret: @oauth_application.plaintext_secret }
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @oauth_application.update(oauth_application_params)
      redirect_to @oauth_application, notice: "OAuth application was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Only a hash of the secret is stored, so a lost secret can't be shown
  # again; this issues a new one and shows it once.
  def regenerate_secret
    @oauth_application.renew_secret
    @oauth_application.save!
    redirect_to @oauth_application, notice: "A new client secret was issued. The old one no longer works.",
      flash: { client_secret: @oauth_application.plaintext_secret }, status: :see_other
  end

  def destroy
    @oauth_application.destroy!
    redirect_to oauth_applications_url, notice: "OAuth application was successfully destroyed.", status: :see_other
  end

  private

  def set_oauth_application
    @oauth_application = authorize policy_scope(OauthApplication).find(params[:id])
  end

  def oauth_application_params
    params.require(:oauth_application).permit(:name, :redirect_uri, :confidential, selected_scopes: [])
  end
end
