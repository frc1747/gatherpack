class FormAudienceRulesController < InternalController
  before_action :require_feature
  before_action :set_form

  # POST /forms/1/audience_rules
  def create
    @rule = authorize @form.form_audience_rules.build(rule_params)

    if @rule.save
      redirect_to edit_form_path(@form, anchor: "audience"), notice: "#{@rule.description}: added. The form now asks #{helpers.pluralize(@form.audience.count, "person", plural: "people")}.", status: :see_other
    else
      redirect_to edit_form_path(@form, anchor: "audience"), alert: "That rule couldn't be added: #{@rule.errors.full_messages.to_sentence}.", status: :see_other
    end
  end

  # DELETE /forms/1/audience_rules/1
  def destroy
    @rule = authorize @form.form_audience_rules.find(params[:id])
    @rule.destroy!
    redirect_to edit_form_path(@form, anchor: "audience"), notice: "#{@rule.description}: removed. Anyone no longer asked keeps the answers they gave.", status: :see_other
  end

  private
    def set_form
      @form = Form.find(params[:form_id])
    end

    def rule_params
      params.require(:form_audience_rule).permit(:effect, :target_type, :team_id, :badge_id, :person_id, :include_managers)
    end

    def require_feature
      redirect_to root_path, notice: "Forms are turned off" unless GatherPack::Features.enabled?(:forms)
    end
end
