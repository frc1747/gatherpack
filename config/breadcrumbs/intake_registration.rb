crumb :intake_registrations do |team|
  link "Registrations", intake_registrations_path
  parent :team, team if team
end

crumb :intake_registration do |registration|
  if registration.new_record?
    link "New registration"
  else
    link registration.title, intake_registration_path(registration)
  end
  parent :intake_registrations
end

crumb :intake_registration_waiting do |registration|
  link "Waiting to finish", waiting_intake_registration_path(registration)
  parent :intake_registration, registration
end

crumb :intake_spam_person do |person|
  link "Delete #{person.display_name}"
  parent :membership_applications, person
end
