# Checklists' routes are always drawn; its controllers send people away
# while the feature is off. Also the shared steps for checking a change's
# impact on an active checklist before it's saved (spec §9.4).
module ChecklistsFeature
  extend ActiveSupport::Concern

  included do
    before_action :require_checklists_feature
  end

  private

  def require_checklists_feature
    redirect_to root_path, notice: "Checklists are turned off" unless Checklists.enabled?
  end

  def set_checklist
    @checklist = policy_scope(Checklist).find(params[:checklist_id])
  end

  # Changes to an active checklist show their impact first, unless confirmed.
  def needs_confirmation?
    @checklist.active? && params[:confirmed].blank?
  end

  # The checklist's items with their rules and children loaded, for drafting
  # a change in memory.
  def item_tree
    @checklist.top_level_items.includes(:checklist_rules, children: [ :checklist_rules, { children: :checklist_rules } ]).to_a
  end

  def find_in_tree(tree, id)
    tree.each do |item|
      return item if item.id == id

      found = find_in_tree(item.children.to_a, id)
      return found if found
    end
    nil
  end

  # Shows what the change would do, with a button that repeats the request
  # confirmed. fields are the request's params to send again.
  def render_impact(impact, url:, method:, fields: {})
    render "checklists/confirm", status: :unprocessable_entity,
      locals: { impact: impact, url: url, method: method, fields: fields }
  end
end
