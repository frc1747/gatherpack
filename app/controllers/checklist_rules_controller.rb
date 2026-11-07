class ChecklistRulesController < InternalController
  include ChecklistsFeature

  before_action :set_checklist

  # POST /checklists/1/rules
  def create
    rule = authorize @checklist.checklist_rules.new(rule_params)

    if rule.save
      redirect_to setup_path(rule), notice: "Rule added.", status: :see_other
    else
      redirect_to setup_path(rule), alert: rule.errors.full_messages.to_sentence, status: :see_other
    end
  end

  # DELETE /checklists/1/rules/1
  def destroy
    rule = authorize @checklist.checklist_rules.find(params[:id])
    rule.destroy!
    redirect_to setup_path(rule), notice: "Rule removed.", status: :see_other
  end

  private

  def setup_path(rule)
    rule.item ? edit_checklist_checklist_item_path(@checklist, rule.item) : checklist_path(@checklist, anchor: "setup")
  end

  def rule_params
    permitted = params.require(:checklist_rule).permit(:item_id, :effect, :target_type, :team_id, :badge_id, :person_id, :include_managers)
    permitted[:item_id] = nil unless @checklist.checklist_items.where(id: permitted[:item_id]).exists?
    permitted
  end
end
