module IntakeHelper
  # Teams the signed-in person can put on a registration's lists.
  def intake_manageable_teams
    person = current_user&.person
    return Team.none unless person
    (current_user.admin ? Team.all : person.all_managed_teams).order(:name)
  end

  def intake_status_label(application)
    case application.status
    when "pending"
      Intake.person_needs_guardian?(application.person) && !application.person.guardians.exists? ? "Waiting for a guardian" : "Waiting for review"
    when "approved" then "You're in"
    when "denied" then "Not accepted"
    end
  end

  def intake_source_label(application)
    { "request" => "Own request", "link" => "Registration link", "kiosk" => "Kiosk" }[application.source]
  end

  # "Did you mean" hints for the email field, from intake_domain_hints.
  def intake_domain_hints
    Settings[:intake_domain_hints].to_s.split(",").map(&:strip).compact_blank
  end
end
