module Commitments
  # One email to each person who still owes on any of the given commitments,
  # listing each with what's left and a link to their own page. People who
  # have met everything get nothing. Recipients are the same as an
  # organizer's message: the members of each open progress with a login, so a
  # group's commitments reach every member. Emails are sent as text under a
  # greeting, and addresses are never shown to each other.
  class MonthlyReminder
    include ERB::Util

    SUBJECT = "What you still owe".freeze

    attr_reader :commitments

    def initialize(commitments)
      @commitments = commitments
    end

    # Queues the emails and returns how many people they go to.
    def deliver
      gateway = Gateway[:email_sending]
      owing.each do |address, (person, progresses)|
        SendEmailJob.perform_later(gateway, address, SUBJECT, body_for(person, progresses))
      end
      owing.size
    end

    def body_for(person, progresses)
      items = progresses.map { |progress| "<li>#{h(line_for(progress))}</li>" }.join
      "<p>Hi #{h(person.first_name)},</p>" \
        "<p>You still have #{progresses.size == 1 ? "something" : "#{progresses.size} things"} to do:</p>" \
        "<ul>#{items}</ul>" \
        "<p><a href=\"#{h(Rails.application.routes.url_helpers.person_commitments_url(person))}\">See what's left</a></p>"
    end

    private

    # Email address => [person, the open progresses they're in], one entry
    # per address.
    def owing
      @owing ||= commitments.each_with_object({}) do |commitment, all|
        commitment.progress.values.uniq.reject(&:met?).each do |progress|
          progress.members.each do |person|
            address = person.user&.email
            (all[address] ||= [ person, [] ]).last << progress if address.present?
          end
        end
      end
    end

    def line_for(progress)
      "#{progress.commitment.title}: #{progress.remaining} #{progress.commitment.unit} to go " \
        "(#{ApplicationController.helpers.commitment_summary(progress)})"
    end
  end
end
