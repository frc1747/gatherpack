# Registration checklists on intake's pages: the checklist panel on
# /join/:slug/me, the counts beside applications, and the setup choices.
module IntakeChecklistsHelper
  # Active checklists the signed-in person runs, for a registration to
  # point to.
  def intake_choosable_checklists
    person = current_user&.person
    @intake_choosable_checklists ||= policy_scope(Checklist).where(status: :active).order(:title).to_a
      .select { |checklist| checklist.organizer?(person) }
  end

  # { person_id => Checklists::Status } on the registration's checklist for
  # these people, as the signed-in person may see them. Empty without an
  # active checklist.
  def intake_registration_checklist_statuses(registration, people)
    @intake_registration_checklist_statuses ||= {}
    @intake_registration_checklist_statuses[registration.id] ||= begin
      checklist = registration.active_checklist
      viewer = current_user&.person
      checklist && viewer ? Checklists.status_for(checklist, people, viewer: viewer) : {}
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

  # Who has to act on an item that isn't done, for the managers deciding:
  # "Riley", "Riley or a guardian", or "a leader". Read from the item's fix:
  # a confirmation goes by who the item lets confirm; a link is the
  # person's to follow (or a guardian's, for someone who needs one); a fix
  # that only says to ask someone is a leader's. Nil when it's done or the
  # viewer sees only its status.
  def intake_item_owner(application, entry)
    return if entry.met? || entry.exempt? || !entry.full?

    person = application.person
    themselves = Intake.person_needs_guardian?(person) ? "#{person.first_name} or a guardian" : person.first_name
    fix = entry.fix || {}
    if fix["action"] == "attest"
      { "manager" => "a leader", "guardian" => "#{person.first_name} or a guardian" }.fetch(entry.item.config["attested_by"].to_s, person.first_name)
    elsif fix["path"].present? || !fix["label"].to_s.start_with?("Ask")
      themselves
    else
      "a leader"
    end
  end

  # The form attribute that ties a row's checkbox to the bulk form above
  # the team's applications.
  def intake_bulk_form_id(team)
    "intake-bulk-#{team.id}"
  end
end
