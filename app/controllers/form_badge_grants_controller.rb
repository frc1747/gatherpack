class FormBadgeGrantsController < InternalController
  before_action :require_feature
  before_action :set_form
  before_action -> { redirect_to edit_form_path(@form, tab: "permissions"), alert: "Badges are turned off.", status: :see_other unless Form.badges_enabled? }

  # POST /forms/1/badge_grants
  def create
    @grant = authorize @form.form_badge_grants.build(params.require(:form_badge_grant).permit(:badge_id, :access))

    if @grant.save
      redirect_to edit_form_path(@form, tab: "permissions"), notice: "#{@grant.identifier_name}: added.", status: :see_other
    else
      redirect_to edit_form_path(@form, tab: "permissions"), alert: "That badge couldn't be added: #{@grant.errors.full_messages.to_sentence}.", status: :see_other
    end
  end

  # DELETE /forms/1/badge_grants/1
  def destroy
    @grant = authorize @form.form_badge_grants.find(params[:id])
    @grant.destroy!
    redirect_to edit_form_path(@form, tab: "permissions"), notice: "#{@grant.badge.name} holders no longer have access through the badge.", status: :see_other
  end

  private
    def set_form
      @form = Form.find(params[:form_id])
    end

    def require_feature
      redirect_to root_path, notice: "Forms are turned off" unless GatherPack::Features.enabled?(:forms)
    end
end
