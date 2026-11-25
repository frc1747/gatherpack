class ChecklistGrantsController < InternalController
  include ChecklistsFeature

  before_action :set_checklist

  # POST /checklists/1/grants
  def create
    grant = authorize @checklist.checklist_grants.new(params.require(:checklist_grant).permit(:badge_id, :team_id, :access, item_ids: []))
    grant.created_by = current_user.person
    refused = grant.access.present? ? grant.refused_items(current_user.person) : []
    if refused.any?
      return redirect_to(checklist_section_path("access"),
        alert: "You can't grant access to #{refused.map(&:label).to_sentence}; ask someone who can.", status: :see_other)
    end

    if grant.save
      redirect_to checklist_section_path("access"), notice: "#{grant.holder_name} can now see it.", status: :see_other
    else
      redirect_to checklist_section_path("access"), alert: grant.errors.full_messages.to_sentence, status: :see_other
    end
  end

  # DELETE /checklists/1/grants/1
  def destroy
    grant = authorize @checklist.checklist_grants.find(params[:id])
    grant.destroy!
    redirect_to checklist_section_path("access"), notice: "Access removed.", status: :see_other
  end
end
