class ChecklistExcusesController < InternalController
  include ChecklistsFeature

  before_action :set_checklist

  # GET /checklists/1/excuses/new?item_id=..&person_id=..
  def new
    @excuse = authorize ChecklistExcuse.new(item: find_item(params[:item_id]), person: find_person(params[:person_id]))
  end

  # POST /checklists/1/excuses
  def create
    attributes = params.require(:checklist_excuse).permit(:item_id, :person_id, :reason, :expires_on)
    @excuse = ChecklistExcuse.new(attributes.except(:item_id, :person_id).merge(item: find_item(attributes[:item_id]),
      person: find_person(attributes[:person_id]), created_by: current_user.person))
    authorize @excuse

    if @excuse.save
      redirect_to checklist_path(@checklist), notice: "#{@excuse.person.display_name} excused from #{@excuse.item.label}.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  # DELETE /checklists/1/excuses/1
  def destroy
    excuse = authorize ChecklistExcuse.where(item_id: @checklist.checklist_items.select(:id)).find(params[:id])
    excuse.destroy!
    redirect_to checklist_path(@checklist), notice: "Excuse removed.", status: :see_other
  end

  private

  def find_item(id)
    @checklist.checklist_items.find(id)
  end

  # Someone the checklist covers.
  def find_person(id)
    Checklists.people_covered_by(@checklist).find(id)
  end
end
