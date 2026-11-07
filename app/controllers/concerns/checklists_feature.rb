# Checklists' routes are always drawn; its controllers send people away
# while the feature is off.
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
end
