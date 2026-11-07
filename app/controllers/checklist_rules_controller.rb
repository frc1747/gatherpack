class ChecklistRulesController < InternalController
  include ChecklistsFeature

  before_action :set_checklist

  # POST /checklists/1/rules
  def create
    rule = authorize @checklist.checklist_rules.new(rule_params)

    if rule.valid? && needs_confirmation? && (impact = rule_impact(rule, :add)).any?
      return render_impact(impact, url: checklist_checklist_rules_path(@checklist), method: :post,
        fields: { checklist_rule: rule_params.to_h })
    end

    if rule.save
      redirect_to setup_path(rule), notice: "Rule added.", status: :see_other
    else
      redirect_to setup_path(rule), alert: rule.errors.full_messages.to_sentence, status: :see_other
    end
  end

  # DELETE /checklists/1/rules/1
  def destroy
    rule = authorize @checklist.checklist_rules.find(params[:id])

    if needs_confirmation? && (impact = rule_impact(rule, :remove)).any?
      return render_impact(impact, url: checklist_checklist_rule_path(@checklist, rule), method: :delete)
    end

    rule.destroy!
    redirect_to setup_path(rule), notice: "Rule removed.", status: :see_other
  end

  private

  # The impact of adding or removing the rule, evaluated in memory.
  def rule_impact(rule, change)
    if rule.item_id.nil?
      rules = @checklist.population_rules.to_a.reject { |existing| existing.id == rule.id }
      rules << rule if change == :add
      return Checklists::Impact.new(@checklist, rules: rules)
    end

    tree = item_tree
    item = find_in_tree(tree, rule.item_id)
    rules = item.checklist_rules.to_a.reject { |existing| existing.id == rule.id }
    rules << rule if change == :add
    item.association(:checklist_rules).target = rules
    Checklists::Impact.new(@checklist, items: tree)
  end

  def setup_path(rule)
    rule.item ? edit_checklist_checklist_item_path(@checklist, rule.item) : checklist_path(@checklist, anchor: "setup")
  end

  def rule_params
    permitted = params.require(:checklist_rule).permit(:item_id, :effect, :target_type, :team_id, :badge_id, :person_id, :include_managers)
    permitted[:item_id] = nil unless @checklist.checklist_items.where(id: permitted[:item_id]).exists?
    permitted
  end
end
