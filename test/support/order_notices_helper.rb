# Reads the notices a test sent. Needs ActiveJob::TestHelper.
module OrderNoticesHelper
  def enqueued_emails
    enqueued_jobs.select { |job| job[:job] == SendEmailJob }.map { |job| job[:args][1..3] }
  end

  # The addresses the emails went to, sorted.
  def emailed
    enqueued_emails.map(&:first).sort
  end

  def addresses(*people)
    people.map { |person| person.user.email }.sort
  end

  # The body of the one email sent to the person.
  def email_to(person)
    enqueued_emails.find { |address, _subject, _body| address == person.user.email }&.last
  end
end
