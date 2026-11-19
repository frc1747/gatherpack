# The Forms tab on a profile: every form about that person the viewer can
# see. A separate controller, so PeopleController is untouched.
class PersonFormsController < InternalController
  before_action :require_feature

  # GET /people/1/forms
  def show
    @person = Person.find(params[:person_id])
    authorize @person, :show?
    return redirect_to person_path(@person), alert: "You can't see this person's forms.", status: :see_other unless helpers.person_forms_tab?(@person)

    @entries = helpers.person_form_entries(@person, current_user.person)
    @ward_entries = helpers.ward_form_entries(@person, current_user.person)
  end

  private
    def require_feature
      redirect_to root_path, notice: "Forms are turned off" unless GatherPack::Features.enabled?(:forms)
    end
end
