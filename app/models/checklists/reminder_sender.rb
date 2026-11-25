module Checklists
  # Sends checklist reminders: one email per recipient, however many
  # checklists remind them (the schedule passes every checklist due that
  # day at once, so nobody gets two checklist reminders in a day). Records
  # each checklist's send (ChecklistReminder, counts only).
  #
  # A scheduled checklist set to go through the summary email leaves out
  # people who chose the summary for checklist reminders
  # (Checklists::ReminderDigest), who see it there, and people who turned
  # them off.
  #
  # The phone-notifications connector prepends deliver to follow each email
  # with a notification built from the same message.
  class ReminderSender
    Request = Data.define(:checklist, :guardians, :person_ids) do
      def initialize(checklist:, guardians: false, person_ids: nil)
        super
      end
    end

    attr_reader :requests, :by, :note

    def initialize(requests, by: nil, note: nil, scheduled: false)
      @requests = Array(requests)
      @by = by
      @note = note
      @scheduled = scheduled
    end

    def scheduled?
      @scheduled
    end

    def builders
      @builders ||= requests.map do |request|
        ReminderBuilder.new(request.checklist, guardians: request.guardians, person_ids: request.person_ids)
      end
    end

    # The entries going out, by email or in the summary.
    def entries
      @entries ||= builders.flat_map(&:entries).reject { |entry| route(entry) == :off }
    end

    # One message per recipient emailed.
    def messages
      @messages ||= entries.select { |entry| route(entry) == :email }.group_by { |entry| entry.recipient.id }
        .map { |_, theirs| ReminderMessage.new(theirs.first.recipient, theirs, note: note) }
        .sort_by { |message| message.recipient.display_name.to_s }
    end

    # The messages a person would get, and those their guardians would get
    # about them: what the preview shows for that person.
    def messages_about(person)
      messages.select { |message| message.recipient.id == person.id || message.entries.any? { |entry| entry.subject.id == person.id } }
    end

    def recipient_count(checklist = nil)
      recipients(checklist).size
    end

    def guardian_count(checklist = nil)
      recipients(checklist, guardians_only: true).size
    end

    # Emails each message and records each checklist's send. Returns the
    # ChecklistReminder records.
    def send!
      messages.each { |message| deliver(message) }
      requests.map(&:checklist).uniq.map do |checklist|
        checklist.checklist_reminders.create!(sent_by: by, sent_at: Time.current, scheduled: scheduled?,
          recipient_count: recipient_count(checklist), guardian_count: guardian_count(checklist))
      end
    end

    private

    def deliver(message)
      subject, body = ChecklistReminderMailer.render(message.payload)
      SendEmailJob.perform_later(Gateway[:email_sending], message.email, subject, body)
    end

    def recipients(checklist, guardians_only: false)
      chosen = entries.select { |entry| checklist.nil? || entry.checklist.id == checklist.id }
      chosen = chosen.select(&:guardian?) if guardians_only
      chosen.map { |entry| entry.recipient.id }.uniq
    end

    # :email, :summary or :off for an entry.
    def route(entry)
      return :email unless scheduled? && entry.checklist.reminder_via_digest?

      (@routes ||= {})[entry.recipient.id] ||= case ReminderDigest.delivery_for(entry.recipient)
      when :each then :email
      when :off then :off
      else :summary
      end
    end
  end
end
