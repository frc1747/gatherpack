# One recipient's account reminder: their items (Accounting::Reminders) from
# every rule reminding them that day. The email (AccountingMailer) and the
# summary section are drawn from it, so they say the same.
#
# payload is plain text and URLs only, with each item's level applied:
# rule names, status labels, milestone names and dates, and with
# "everything" the amount to catch up and the pay link. Never a memo, note
# or credit reason, and never that someone is on a payment plan.
class Accounting::ReminderMessage
  include Rails.application.routes.url_helpers

  SIGN_IN = "You have an account update. Sign in to see it.".freeze

  attr_reader :recipient, :items

  def initialize(recipient, items)
    @recipient = recipient
    @items = items.sort_by { |item| [ item.rule.position.to_i, item.rule.name.to_s.downcase, item.guardian? ? 1 : 0, item.person.identifier_name.to_s ] }
  end

  def email
    recipient.user&.email
  end

  def people
    items.map(&:person).uniq(&:id)
  end

  def subject_line
    "#{site_title} - #{headline}"
  end

  # "Reminder: <rule>" when it names exactly one rule, else a line that
  # names none. A rule whose reminders just say "sign in" is never named.
  def headline
    rules = items.map(&:rule).uniq(&:id)
    rules.one? && items.none? { |item| item.level == "sign_in" } ? "Reminder: #{rules.first.name}" : "Account reminder"
  end

  def payload
    {
      "to" => email,
      "subject" => subject_line,
      "greeting" => "Hi #{recipient.first_name.to_s.strip.presence || recipient.identifier_name},",
      "sections" => sections,
      "button_label" => people.one? ? "Open Account" : "Open #{site_title}",
      "button_url" => people.one? ? person_accounting_url(people.first) : root_url
    }
  end

  # [{ "heading", "text", "lines" => [String], "link_label", "link_url" }]
  # A "sign in" reminder is one line per person, however many rules say it.
  def sections
    signed = Set.new
    items.filter_map do |item|
      if item.level == "sign_in"
        next if signed.include?(item.person.id)

        signed << item.person.id
        { "heading" => nil, "text" => sign_in_text(item), "lines" => [] }
      else
        shown_section(item)
      end
    end.then { |list| merge_sections(list) }
  end

  private
    # One section per rule and person, however many milestones remind them.
    def merge_sections(list)
      list.chunk_while { |a, b| a["heading"] && a["heading"] == b["heading"] }.map do |group|
        group.first.merge("lines" => group.flat_map { |section| section["lines"] }.uniq, "link_url" => group.filter_map { |section| section["link_url"] }.first,
          "link_label" => group.filter_map { |section| section["link_label"] }.first)
      end
    end

    def shown_section(item)
      rule = item.rule
      result = item.result
      milestone = item.milestone || {}
      heading = item.guardian? ? "#{rule.name}: #{item.person.identifier_name}" : rule.name
      date = format_date(milestone["due_on"])
      line = if item.overdue?
        "#{rule.label_for(result.value)}: #{milestone["name"]} was due #{date}."
      else
        "#{rule.label_for(result.value)}. #{milestone["name"]} is due #{date}."
      end
      lines = [ line ]
      section = { "heading" => heading, "text" => nil }
      if item.level == "everything"
        catch_up = milestone["catch_up_cents"].to_i
        lines << "#{Money.new(catch_up).format} to meet #{milestone["name"]}." if catch_up.positive?
        if (url = pay_url(rule, result))
          section.merge!("link_label" => "Pay online", "link_url" => url)
        end
      end
      section.merge("lines" => lines)
    end

    def sign_in_text(item)
      return SIGN_IN unless item.guardian?

      "#{item.person.first_name.to_s.strip.presence || item.person.identifier_name} has an account update. Sign in to see it."
    end

    # The first pay link of a charge with something still owed, where the
    # rule shows pay links.
    def pay_url(rule, result)
      return unless rule.pay_links?

      result.charges.find { |charge| charge["pay_url"].present? && charge["balance_cents"].to_i.positive? }&.fetch("pay_url")
    end

    def format_date(value)
      date = value.is_a?(Date) ? value : Date.iso8601(value.to_s)
      I18n.l(date, format: :short)
    rescue Date::Error
      value.to_s
    end

    def site_title
      Settings[:title].presence || "GatherPack"
    end

    def default_url_options
      Rails.application.routes.default_url_options
    end
end
