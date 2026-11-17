module Commitments
  # An organizer's message to everyone who hasn't met a commitment, one
  # email each so no one sees anyone else's address. The organizer's text
  # goes out as text, like the sign-up sheet message: escaped, with blank
  # lines as paragraphs and single line breaks kept, under a greeting and a
  # line saying who sent it about which commitment.
  class Message
    include ERB::Util

    attr_reader :commitment, :from

    def initialize(commitment, from:)
      @commitment = commitment
      @from = from
    end

    # Sends the message and returns how many people it went to.
    def deliver(subject:, body:)
      open = commitment.progress.values.uniq.reject(&:met?).flat_map(&:members)
      people = open.select { |person| person.user&.email.present? }.uniq { |person| person.user.email }
      gateway = Gateway[:email_sending]
      people.each { |person| SendEmailJob.perform_later(gateway, person.user.email, subject, body_for(person, body)) }
      people.size
    end

    def body_for(person, body)
      "<p>Hi #{h(person.first_name)},</p>" \
        "<p>From #{h(from&.display_name || "the organizers")}, about #{h(commitment.title)}:</p>" \
        "#{simple_format(body)}"
    end

    private

    def simple_format(text)
      text.to_s.split(/\n{2,}/).map { |paragraph| "<p>#{h(paragraph.strip).gsub("\n", "<br>")}</p>" }.join
    end
  end
end
