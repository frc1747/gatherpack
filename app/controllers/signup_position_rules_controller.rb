class SignupPositionRulesController < InternalController
  include SignupsFeature

  before_action :set_signup_position

  # POST /signup_sheets/1/signup_positions/1/signup_position_rules
  def create
    @rule = authorize @signup_position.signup_position_rules.build(rule_params)
    return refuse_teams if teams_out_of_reach?

    if @rule.save
      redirect_to edit_path, notice: "Rule added: #{@rule.description}.", status: :see_other
    else
      redirect_to edit_path, alert: "That rule couldn't be added: #{error_text}.", status: :see_other
    end
  end

  # PATCH /signup_sheets/1/signup_positions/1/signup_position_rules/1
  def update
    @rule = authorize @signup_position.signup_position_rules.find(params[:id])
    @rule.assign_attributes(rule_params.except(:kind))
    return refuse_teams if teams_out_of_reach?

    if @rule.save
      redirect_to edit_path, notice: "Rule saved: #{@rule.description}.", status: :see_other
    else
      redirect_to edit_path, alert: "That rule couldn't be saved: #{error_text}.", status: :see_other
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

    def teams_out_of_reach?
      @rule.team? && (@rule.team_ids - team_choice_ids).any?
    end

    def refuse_teams
      redirect_to edit_path, alert: "Pick #{@signup_sheet.team.name} or teams below it.", status: :see_other
    end

    # The "one rule of each kind" message reads as a sentence by itself.
    def error_text
      @rule.errors.map { |error| error.attribute == :kind ? error.message : error.full_message }.to_sentence
    end

    def rule_params
      params.require(:signup_position_rule).permit(:kind, :min_age, :max_age, badge_ids: [], team_ids: [])
    end
end
