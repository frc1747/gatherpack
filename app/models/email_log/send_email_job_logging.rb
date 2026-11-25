module EmailLog
  # Prepended onto SendEmailJob: writes a log entry before handing the email
  # to the gateway and stores the id the gateway returns. Callers that know
  # who the email is for and what it's about pass person: and about:; the
  # four-argument calls keep working.
  module SendEmailJobLogging
    extend ActiveSupport::Concern

    prepended do
      # After the last attempt (or an error that isn't retried).
      after_discard do |job, error|
        job.mark_logged_email_failed(error)
      end
    end

    def perform(gateway, address, subject, body, person: nil, about: nil)
      return super(gateway, address, subject, body) unless gateway && EmailLog.enabled?

      entry = logged_email(gateway, address, subject, person, about)
      result = super(gateway, address, subject, body)
      entry.sent!(gateway.try(:provider_message_id, result))
      result
    end

    def mark_logged_email_failed(error)
      SentEmail.find_by(job_id: job_id, status: "sending")&.failed!(error)
    end

    private
      # One entry per job, however many times it's retried.
      def logged_email(gateway, address, subject, person, about)
        SentEmail.create_with(
          gateway: gateway,
          address: address.to_s,
          subject: subject,
          person: person || person_for(address),
          about: about
        ).find_or_create_by!(job_id: job_id)
      end

      # The person who signs in with this address, when the caller didn't say.
      def person_for(address)
        Person.joins(:user).find_by(users: { email: address.to_s.downcase })
      end
  end
end
