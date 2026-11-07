class ChecklistGrantsController < InternalController
  include ChecklistsFeature

  before_action :set_checklist

  # POST /checklists/1/grants
  def create
    grant = authorize @checklist.checklist_grants.new(params.require(:checklist_grant).permit(:badge_id, :team_id, :access, item_ids: []))

    if grant.save
      redirect_to checklist_path(@checklist, anchor: "setup"), notice: "#{grant.holder_name} can now see it.", status: :see_other
    else
      redirect_to checklist_path(@checklist, anchor: "setup"), alert: grant.errors.full_messages.to_sentence, status: :see_other
    end
  end

  # DELETE /checklists/1/grants/1
  def destroy
    grant = authorize @checklist.checklist_grants.find(params[:id])
    grant.destroy!
    redirect_to checklist_path(@checklist, anchor: "setup"), notice: "Access removed.", status: :see_other
  end
end
