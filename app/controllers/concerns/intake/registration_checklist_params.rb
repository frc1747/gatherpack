# Prepended to Intake::RegistrationsController from
# config/initializers/intake_checklist.rb: a registration's checklist is one
# the person runs (Checklist#organizer?). One already chosen that they don't
# run is kept: someone else put it there.
module Intake::RegistrationChecklistParams
  private

  def registration_params
    permitted = super
    return permitted unless params[:intake_registration]&.key?(:checklist_id)

    id = params[:intake_registration][:checklist_id].presence
    chosen = id && helpers.intake_choosable_checklists.find { |checklist| checklist.id == id }
    permitted[:checklist_id] = id.nil? ? nil : (chosen&.id || @registration&.checklist_id)
    permitted
  end
end
