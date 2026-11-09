class SignupAudienceRulesController < InternalController
  include SignupsFeature

  before_action :set_signup_sheet

  # POST /signup_sheets/1/signup_audience_rules
  def create
    @rule = authorize @signup_sheet.signup_audience_rules.build(rule_params)
    if @rule.target_badge? && !GatherPack::Features.enabled?(:badges)
      return redirect_to edit_path, alert: "Badges are turned off.", status: :see_other
    end
    if @rule.target_team? && @rule.team_id && !admin? && !team_choice_ids.include?(@rule.team_id)
      return redirect_to edit_path, alert: "Pick #{@signup_sheet.team.name} or a team below it.", status: :see_other
    end

    if @rule.save
      redirect_to edit_path, notice: "#{@rule.description}: added. The sheet is now open to #{helpers.pluralize(@signup_sheet.audience.count, "person", plural: "people")}.", status: :see_other
    else
      redirect_to edit_path, alert: "That rule couldn't be added: #{@rule.errors.full_messages.to_sentence}.", status: :see_other
    end
  end

  # DELETE /signup_sheets/1/signup_audience_rules/1
  def destroy
    @rule = authorize @signup_sheet.signup_audience_rules.find(params[:id])
    @rule.destroy!
    redirect_to edit_path, notice: "#{@rule.description}: removed. Anyone already signed up stays signed up.", status: :see_other
  end

  private
    def set_signup_sheet
      @signup_sheet = SignupSheet.find(params[:signup_sheet_id])
    end

    def edit_path
      edit_signup_sheet_path(@signup_sheet, anchor: "audience")
    end

    def team_choice_ids
      [ @signup_sheet.team_id ] + @signup_sheet.team.all_descendant_ids
    end

    def rule_params
      params.require(:signup_audience_rule).permit(:effect, :target_type, :team_id, :badge_id, :person_id, :include_managers)
    end
end
