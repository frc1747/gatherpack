# Registration checklists on intake's pages: the checklist panel on
# /join/:slug/me, the counts beside applications, and the setup choices.
module IntakeChecklistsHelper
  # Checklists the signed-in person runs, for a registration to point to.
  def intake_choosable_checklists
    person = current_user&.person
    @intake_choosable_checklists ||= policy_scope(Checklist).where.not(status: :archived).order(:title).to_a
      .select { |checklist| checklist.organizer?(person) }
  end

  # { person_id => Checklists::Status } on the registration's checklist for
  # these people, as the signed-in person may see them. Empty when there is
  # no checklist, or it's a draft they don't run.
  def intake_registration_checklist_statuses(registration, people)
    @intake_registration_checklist_statuses ||= {}
    @intake_registration_checklist_statuses[registration.id] ||= begin
      checklist = registration.active_checklist
      viewer = current_user&.person
      if checklist.nil? || viewer.nil? || checklist.archived? || (checklist.draft? && !checklist.organizer?(viewer))
        {}
      else
        Checklists.status_for(checklist, people, viewer: viewer)
      end
    end
  end

  # The applicant's status beside an application, loaded for every
  # application on the page at once (the team's pending applications, or a
  # person's applications) when the first row asks.
  def intake_application_checklist(application)
    @intake_application_checklists ||= Intake::ApplicationChecklists.new(@pending_applications || @membership_applications || [ application ],
      current_user&.person)
    @intake_application_checklists.status_for(application)
  end

  # The form attribute that ties a row's checkbox to the bulk form above
  # the team's applications.
  def intake_bulk_form_id(team)
    "intake-bulk-#{team.id}"
  end
end
