class SignupPositionRulesController < InternalController
  before_action :set_signup_position

  # POST /signup_sheets/1/signup_positions/1/signup_position_rules
  def create
    @rule = authorize @signup_position.signup_position_rules.build(rule_params)
    if @rule.team_id && !team_choice_ids.include?(@rule.team_id)
      return redirect_to edit_path, alert: "Pick #{@signup_sheet.team.name} or a team below it.", status: :see_other
    end

    if @rule.save
      redirect_to edit_path, notice: "Rule added: #{@rule.description}.", status: :see_other
    else
      redirect_to edit_path, alert: "That rule couldn't be added: #{@rule.errors.full_messages.to_sentence}.", status: :see_other
    end
  end

  # DELETE /signup_sheets/1/signup_positions/1/signup_position_rules/1
  def destroy
    @rule = authorize @signup_position.signup_position_rules.find(params[:id])
    @rule.destroy!
    redirect_back_or_to edit_path, notice: "Rule removed: #{@rule.description}.", status: :see_other
  end

  private
    def set_signup_position
      @signup_sheet = SignupSheet.find(params[:signup_sheet_id])
      @signup_position = @signup_sheet.signup_positions.find(params[:signup_position_id])
    end

    def edit_path
      edit_signup_sheet_signup_position_path(@signup_sheet, @signup_position, anchor: "rules")
    end

    def team_choice_ids
      [ @signup_sheet.team_id ] + @signup_sheet.team.all_descendant_ids
    end

    def rule_params
      params.require(:signup_position_rule).permit(:kind, :min_age, :max_age, :team_id, badge_ids: [])
    end
end
