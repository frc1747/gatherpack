class ChecklistListsController < InternalController
  include ChecklistsFeature

  before_action :set_checklist

  # GET /checklists/1/lists/1
  def show
    @list = authorize @checklist.checklist_lists.find(params[:id])
    @rows = @list.rows_for(current_user.person)
  end

  # POST /checklists/1/lists
  def create
    authorize @checklist.checklist_lists.new
    list = ChecklistList.record!(@checklist, by: current_user.person, note: params.dig(:checklist_list, :note))
    redirect_to checklist_checklist_list_path(@checklist, list), notice: "List recorded.", status: :see_other
  end
end
