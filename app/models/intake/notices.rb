# The emails intake sends, through SendEmailJob and the email gateway.
# Short and plain: first names and the team name only, nothing else from
# the entry. Nothing goes to a person who needs a guardian until one is
# linked; until then their notices go to their guardians, or nowhere.
#
# An email that carries a link is built and sent inside an intake job
# (now: true), so the link's token never sits in the job queue; the queue
# only ever holds a record's id.
module Intake::Notices
  # Tests swap this in to see what would be sent at once.
  mattr_accessor :sender

  module_function

  def finish_joining(entry, token)
    deliver(entry.email, "Finish joining #{entry.team_names}", "finish_joining",
      first_name: entry.first_name, team_names: entry.team_names,
      url: Rails.application.routes.url_helpers.intake_verification_url(token: token),
      hours: Intake.setting(:intake_link_hours, 48), now: true)
  end

  def existing_account(entry)
    deliver(entry.email, "Sign in to finish joining #{entry.team_names}", "existing_account",
      first_name: entry.first_name, team_names: entry.team_names,
      url: Rails.application.routes.url_helpers.intake_join_url(slug: entry.registration.slug), now: true)
  end

  def confirm_guardian(row, token)
    ward = row.ward
    team_names = row.entry.team_names.presence || row.entry.registration.team.name
    deliver(row.facts["email"], "Confirm you are #{ward.first_name}'s guardian", "confirm_guardian",
      guardian_first_name: row.facts["first_name"], first_name: ward.first_name, team_names: team_names,
      url: Rails.application.routes.url_helpers.intake_guardian_confirmation_url(token: token),
      hours: Intake.setting(:intake_link_hours, 48), now: true)
  end

  def confirm_email_change(user, new_email, token)
    deliver(new_email, "Confirm your new email", "confirm_email_change",
      first_name: user.person&.first_name, url: Rails.application.routes.url_helpers.intake_email_change_url(token: token),
      hours: Intake.setting(:intake_link_hours, 48), now: true)
  end

  # One message per manager: "<n> people are waiting to join <team>." per team.
  def digest(manager, lines)
    deliver(manager.user.email, "People waiting to join", "digest", first_name: manager.first_name, lines: lines,
      url: Rails.application.routes.url_helpers.intake_registrations_url)
  end

  def approved(application)
    to_person(application.person, "You're in: #{application.team.name}", "approved",
      first_name: application.person.first_name, team_name: application.team.name)
  end

  def denied(application)
    to_person(application.person, "Your application to #{application.team.name}", "denied",
      first_name: application.person.first_name, team_name: application.team.name,
      reason: application.reviewer_notes.presence)
  end

  # Once, when a registration reaches its cap of unfinished sign-ups.
  def registration_busy(registration)
    registration.team.all_managers_and_admins.filter_map { |manager| manager.user&.email }.uniq.each do |email|
      deliver(email, "#{registration.title} is turning people away", "registration_busy",
        title: registration.title, cap: Intake.setting(:intake_entry_cap, 500),
        url: Rails.application.routes.url_helpers.intake_registration_url(registration))
    end
  end

  # The person's own address, or their guardians' when they need one.
  def to_person(person, subject, template, assigns)
    addresses = if Intake.person_needs_guardian?(person)
      person.guardians.includes(:user).filter_map { |guardian| guardian.user&.email }
    else
      [ person.user&.email ].compact
    end
    addresses.uniq.each { |address| deliver(address, subject, template, **assigns) }
  end

  def deliver(address, subject, template, now: false, **assigns)
    return if address.blank?
    body = ApplicationController.render(template: "intake/mailer/#{template}", assigns: assigns, layout: false)
    if now
      (sender || SendEmailJob.method(:perform_now)).call(Gateway[:email_sending], address, subject, body)
    else
      SendEmailJob.perform_later(Gateway[:email_sending], address, subject, body)
    end
  end
end
