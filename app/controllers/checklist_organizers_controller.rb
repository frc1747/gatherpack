class ChecklistOrganizersController < InternalController
  include ChecklistsFeature

  before_action :set_checklist

  # POST /checklists/1/organizers
  def create
    organizer = authorize @checklist.checklist_organizers.new(person: Person.find_by(id: params.dig(:checklist_organizer, :person_id)))

    if organizer.save
      redirect_to checklist_section_path("organizers"), notice: "#{organizer.person.display_name} can now run it.", status: :see_other
    else
      redirect_to checklist_section_path("organizers"), alert: organizer.errors.full_messages.to_sentence, status: :see_other
    end
  end

  # DELETE /checklists/1/organizers/1
  def destroy
    organizer = authorize @checklist.checklist_organizers.find(params[:id])
    organizer.destroy!
    redirect_to checklist_section_path("organizers"), notice: "Organizer removed.", status: :see_other
  end
end
