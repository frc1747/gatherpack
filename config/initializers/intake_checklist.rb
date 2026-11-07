# Registration checklists: intake shows a checklist's results to the people
# joining and to the managers deciding, and can hold approval until it's
# done. Checklists defines the checks; intake only reads them. Runs after
# intake.rb (initializers load in name order), so these decisions wrap
# intake's own.

# When someone's checklist is done, intake tells them a manager will decide
# (Intake::ChecklistReaction). Subscribed once, outside to_prepare, so a
# development reload doesn't add a second subscriber.
ActiveSupport::Notifications.subscribe("checklist_status_changed.gatherpack") do |event|
  Intake::ChecklistReaction.call(event.payload[:result], event.payload[:previous_status])
end

Rails.application.config.to_prepare do
  Intake::Registration.include(Intake::RegistrationChecklist)
  # A checklist a registration uses can't be deleted (a readable error; the
  # foreign key blocks it too).
  unless Checklist.reflect_on_association(:intake_registrations)
    Checklist.has_many :intake_registrations, class_name: "Intake::Registration", dependent: :restrict_with_error, inverse_of: :checklist
  end

  MembershipApplication.include(Intake::ApplicationChecklist)
  MembershipApplicationsController.include(Intake::ApplicationGating)
  Intake::RegistrationsController.prepend(Intake::RegistrationChecklistParams)
  ChecklistItemsController.prepend(Checklists::KioskItemParams)
end
