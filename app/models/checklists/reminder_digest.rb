module Checklists
  # Scheduled reminders through the summary email, where the summaries seam
  # (GatherPack::Digests) is merged and on. A checklist set to go through
  # the summary sends its scheduled reminder there to each person who chose
  # the summary for checklist reminders; everyone else gets the email.
  # Registered as a section from config/initializers/checklist_reminders.rb
  # only when the seam exists; without it every reminder is an email.
  module ReminderDigest
    KEY = :checklist_reminders

    class << self
      def available?
        defined?(GatherPack::Digests) && GatherPack::Digests.respond_to?(:handles?) ? true : false
      end

      # :each (an email), :daily, :weekly, :both or :off: how the person
      # gets checklist reminders.
      def delivery_for(person)
        return :each unless available? && GatherPack::Digests.handles?(KEY)

        GatherPack::Digests.delivery_for(KEY, person)
      end

      # The person's section: the reminders of checklists that went through
      # the summary since then, drawn as in the email. nil when there are
      # none.
      def html_for(person, since:)
        return unless ChecklistReminder.enabled?

        checklists = Checklist.active.where(reminder_via_digest: true,
          id: ChecklistReminder.scheduled.where(sent_at: since..).select(:checklist_id)).order(:title)
        entries = checklists.flat_map do |checklist|
          ReminderBuilder.new(checklist, guardians: checklist.reminder_guardians?,
            person_ids: [ person.id ] + (checklist.reminder_guardians? ? person.wards.ids : []), recipient_ids: [ person.id ]).entries
        end
        return if entries.empty?

        ChecklistReminderMailer.render_sections(ReminderMessage.new(person, entries).sections)
      end

      def register(digests = GatherPack::Digests)
        digests.register(KEY, label: "Checklist reminders", delivery: -> { :each },
          build: ->(person, since:) {
            html = html_for(person, since: since)
            digests::Section.new(body: html, link: Rails.application.routes.url_helpers.person_checklists_url(person)) if html
          })
      end
    end
  end
end
