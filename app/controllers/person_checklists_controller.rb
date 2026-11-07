# A person's checklists, as the viewer may see them (the profile tab).
class PersonChecklistsController < InternalController
  include ChecklistsFeature

  # GET /people/:person_id/checklists
  def show
    @person = authorize policy_scope(Person).find(params[:person_id]), :show?
    @checklists = Checklists.checklist_for(@person, viewer: current_user.person)
  end
end
