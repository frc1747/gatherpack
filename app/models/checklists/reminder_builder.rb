module Checklists
  # Who one checklist's reminder goes to, and what each recipient may be
  # told about whom.
  #
  # The people reminded are those it covers whose overall isn't complete
  # (not started or in progress): complete, exempt and excused people get
  # nothing. Each is reminded themselves, and with guardians: true their
  # guardians too. A recipient is told about the outstanding items they
  # could see on the site (Checklists::Visibility, through Reader), so an
  # item a guardian can't see stays out of the guardian's email. Only people
  # with an email address are recipients; a recipient who could see nothing
  # outstanding gets nothing.
  class ReminderBuilder
    REMINDED = %w[not_met pending].freeze

    # recipient and subject are People: subject is who the lines are about
    # (the recipient themselves, or a ward). lines are the outstanding
    # top-level ItemStatus entries the recipient may see, in order.
    Entry = Data.define(:recipient, :subject, :checklist, :lines) do
      def guardian?
        recipient.id != subject.id
      end
    end

    attr_reader :checklist, :guardians

    # person_ids narrows who is reminded (the people ticked); recipient_ids
    # narrows who is told (one person's summary section).
    def initialize(checklist, guardians: false, person_ids: nil, recipient_ids: nil)
      @checklist = checklist
      @guardians = guardians
      @only_people = person_ids&.map(&:to_s)
      @only_recipients = recipient_ids&.map(&:to_s)
    end

    # The ids of the people to remind.
    def person_ids
      @person_ids ||= begin
        ids = @only_people || checklist.reported_person_ids
        Reader.new(checklist, nil).overall_statuses(ids).select { |_, status| REMINDED.include?(status) }.keys
      end
    end

    def people
      Person.where(id: person_ids).order(:last_name, :first_name)
    end

    def entries
      @entries ||= begin
        subjects = Person.where(id: person_ids).includes(:user).to_a
        recipients = {}
        about = Hash.new { |hash, key| hash[key] = [] }
        subjects.each do |subject|
          recipients_for(subject).each do |recipient|
            recipients[recipient.id] ||= recipient
            about[recipient.id] << subject
          end
        end

        about.flat_map do |recipient_id, their_subjects|
          recipient = recipients[recipient_id]
          statuses = Reader.new(checklist, recipient).status_for(their_subjects)
          their_subjects.filter_map do |subject|
            lines = outstanding(statuses[subject.id])
            Entry.new(recipient: recipient, subject: subject, checklist: checklist, lines: lines) if lines.any?
          end
        end
      end
    end

    private

    def recipients_for(subject)
      people = [ subject ]
      people.concat(subject.guardians.includes(:user).to_a) if guardians
      people.uniq(&:id).select do |person|
        person.user&.email.present? && (@only_recipients.nil? || @only_recipients.include?(person.id.to_s))
      end
    end

    def outstanding(status)
      return [] unless status

      status.items.select { |entry| entry.item&.counts? && REMINDED.include?(entry.status) }
    end
  end
end
