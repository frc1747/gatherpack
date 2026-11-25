module IntakeHelper
  # Teams the signed-in person can put on a registration's lists.
  def intake_manageable_teams
    person = current_user&.person
    return Team.none unless person
    (current_user.admin ? Team.all : person.all_managed_teams).order(:name)
  end

  # Badges the signed-in person may give, so may put on "Also give these badges".
  def intake_assignable_badges
    return [] unless current_user&.person
    Badge.order(:name).select { |badge| BadgePolicy.new(current_user, badge).update? }
  end

  # A registration's state in words, for its page and list: "Taking
  # registrations until Sep 1", "Opens Sep 1", "Closed Sep 1".
  def intake_registration_state(registration)
    day = ->(time) { l(time.to_date, format: time.year == Time.current.year ? "%b %-d" : "%b %-d, %Y") }
    if registration.closed?
      "Closed #{day.(registration.closes_at)}"
    elsif registration.not_yet_open?
      "Not taking registrations yet. Opens #{day.(registration.opens_at)}"
    elsif registration.closes_at
      "Taking registrations until #{day.(registration.closes_at)}"
    else
      "Taking registrations"
    end
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
