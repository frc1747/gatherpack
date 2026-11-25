module Checklists
  # One recipient's reminder: their entries (Checklists::ReminderBuilder)
  # from every checklist reminding them at once, with what each may say
  # applied (Checklists::EmailLevel). The email (ChecklistReminderMailer),
  # the preview, the phone notification and the summary section are all
  # drawn from it, so they say the same.
  #
  # payload is plain text and URLs only: names, words and summaries the
  # levels allow, nothing else.
  class ReminderMessage
    include Rails.application.routes.url_helpers

    attr_reader :recipient, :entries, :note

    def initialize(recipient, entries, note: nil)
      @recipient = recipient
      @entries = entries.sort_by { |entry| [ entry.checklist.title.to_s.downcase, entry.guardian? ? 1 : 0, entry.subject.display_name.to_s ] }
      @note = note.to_s.gsub("\r\n", "\n").strip.presence
    end

    def email
      recipient.user&.email
    end

    def checklists
      entries.map(&:checklist).uniq
    end

    def subjects
      entries.map(&:subject).uniq(&:id)
    end

    def guardian?
      entries.any?(&:guardian?)
    end

    # The email's subject.
    def subject_line
      "#{site_title} - #{headline}"
    end

    # "Reminder: <checklist>" when it names exactly one checklist, else a
    # line that names none. A checklist at Just "sign in" is never named.
    def headline
      named = checklists.reject { |checklist| hidden?(checklist) }
      named.one? && checklists.one? ? "Reminder: #{named.first.title}" : "Reminder: items to finish"
    end

    # The phone notification: the headline, opening the subject's checklists.
    def push_title
      headline
    end

    def push_path
      subjects.one? ? person_checklists_path(subjects.first) : root_path
    end

    def payload
      {
        "to" => email,
        "subject" => subject_line,
        "greeting" => "Hi #{recipient.first_name.to_s.strip.presence || recipient.display_name},",
        "note" => note,
        "sections" => sections,
        "button_label" => subjects.one? ? "Open Checklists" : "Open #{site_title}",
        "button_url" => subjects.one? ? person_checklists_url(subjects.first) : root_url
      }
    end

    # [{ "heading", "text", "lines" => [{ "name", "word", "summary", "link_label", "link_url" }], "more" }]
    # A checklist at Just "sign in" is one line per person ("You have items
    # to finish..."), however many such checklists remind them.
    def sections
      hidden_said = Set.new
      entries.filter_map do |entry|
        if hidden?(entry.checklist)
          next if hidden_said.include?(entry.subject.id)

          hidden_said << entry.subject.id
          { "heading" => nil, "text" => hidden_text(entry), "lines" => [], "more" => nil }
        else
          shown_section(entry)
        end
      end
    end

    def hidden?(checklist)
      EmailLevel.for_checklist(checklist) == EmailLevel::LEVELS.last
    end

    private

    def shown_section(entry)
      hidden = 0
      lines = entry.lines.filter_map do |line|
        level = EmailLevel.for(line.item)
        case level
        when "sign_in"
          hidden += 1
          nil
        when "name_only"
          { "name" => line.item.label, "word" => line.text }
        else
          { "name" => line.item.label, "word" => line.text, "summary" => (line.summary.presence if line.full? && line.summary != line.text) }
            .merge(fix_link(line))
        end
      end
      heading = entry.guardian? ? "#{entry.checklist.title}: #{entry.subject.display_name}" : entry.checklist.title
      { "heading" => heading, "text" => nil, "lines" => lines, "more" => more_text(hidden, lines.any?) }
    end

    def hidden_text(entry)
      who = entry.guardian? ? "#{entry.subject.first_name.to_s.strip.presence || entry.subject.display_name} has" : "You have"
      "#{who} items to finish in #{site_title}. Sign in to see them."
    end

    def more_text(count, named)
      return if count.zero?

      items = "#{count} #{named ? "more " : ""}#{"item".pluralize(count)}"
      named ? "#{items}. Sign in to see #{count == 1 ? "it" : "them"}." : "#{items} to finish. Sign in to see #{count == 1 ? "it" : "them"}."
    end

    # The item's fix as a link, when it opens a page here that the
    # recipient may open.
    def fix_link(line)
      fix = line.fix
      return {} unless line.full? && fix.is_a?(Hash) && fix["path"].to_s.start_with?("/") && fix_allowed?(fix["requires"])

      { "link_label" => fix["label"].presence || "Fix it", "link_url" => "#{root_url.chomp("/")}#{fix["path"]}" }
    end

    def fix_allowed?(requires)
      return true if requires.blank?

      query = requires["query"].to_s
      return false unless query.match?(/\A[a-z_]+\?\z/) && recipient.user

      record = GlobalID::Locator.locate(requires["record"].to_s)
      policy = record && Pundit.policy(recipient.user, record)
      policy.respond_to?(query) && policy.public_send(query) ? true : false
    rescue ActiveRecord::RecordNotFound, URI::InvalidURIError, Pundit::NotDefinedError
      false
    end

    def site_title
      Settings[:title].presence || "GatherPack"
    end

    def default_url_options
      Rails.application.routes.default_url_options
    end
  end
end
