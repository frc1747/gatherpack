# Sends the email for a new entry. Whether the email already has a login is
# decided here, never in the request, so the public page does the same work
# and says the same thing for every address; only the email differs. Takes
# the entry's id; the link is made and sent here, so no token is queued.
class Intake::EntryEmailJob < ApplicationJob
  queue_as :default

  def perform(entry_id)
    entry = Intake::Entry.find_by(id: entry_id)
    return if entry.nil? || entry.verified_at
    # Nothing goes to a young person's address until a guardian is linked;
    # confirming the guardian sends this again.
    return if entry.facts["needs_guardian"] && entry.person && !entry.person.guardians.exists?

    if !entry.facts["new_login"] && Intake.user_for_email(entry.email)
      Intake::Notices.existing_account(entry)
    else
      Intake::Notices.finish_joining(entry, entry.issue_token!)
    end
  end
end
