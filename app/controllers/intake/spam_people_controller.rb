# Admins delete a person who came in through a registration as spam, with
# their login, after seeing what will go. The deletion is in the audit log.
class Intake::SpamPeopleController < InternalController
  before_action :require_intake_feature
  before_action :set_person

  # GET /registration-spam/:id
  def show
    @spam = Intake::SpamPerson.new(@person)
  end

  # DELETE /registration-spam/:id
  def destroy
    name = @person.display_name
    Intake::SpamPerson.new(@person).destroy!
    redirect_to intake_registrations_path, notice: "Deleted #{name} and their login.", status: :see_other
  end

  private

  def require_intake_feature
    redirect_to root_path, notice: "Registration isn't turned on." unless Intake.enabled?
  end

  def set_person
    @person = Person.find(params[:id])
    authorize @person, policy_class: Intake::SpamPersonPolicy
  end
end
