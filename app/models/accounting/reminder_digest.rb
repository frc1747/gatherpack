# Account reminders through the summary email, where the summaries seam
# (GatherPack::Digests) is merged and summaries are on. The Account Status
# setting "Account Reminders in the Daily Digest" sets the site's choice,
# and each person may choose for themselves (GatherPack::Digests
# .delivery_for). People who chose the summary are logged as reminded
# (AccountingReminder) and see those reminders in it; everyone else gets the
# email. Registered from config/initializers/accounting.rb only when the
# seam exists; without it every reminder is an email.
module Accounting::ReminderDigest
  KEY = :accounting
  SETTING = :accounting_reminders_in_digest

  class << self
    def available?
      defined?(GatherPack::Digests) && GatherPack::Digests.respond_to?(:handles?) && GatherPack::Digests.handles?(KEY) ? true : false
    end

    # :email, :summary or :off: how a reminder reaches the person.
    def route(person)
      return :email unless available?

      case GatherPack::Digests.delivery_for(KEY, person)
      when :each then :email
      when :off then :off
      else :summary
      end
    end

    # The site's choice: :each unless the setting sends them in the daily
    # digest.
    def delivery
      Settings.get(SETTING)&.value == true ? :daily : :each
    end

    # The person's section: the reminders logged for them since then that
    # still stand, drawn as in the email. nil when there are none, or when
    # they get reminders by email.
    def html_for(person, since:)
      return unless Accounting.enabled? && route(person) == :summary

      reminders = AccountingReminder.where(recipient_id: person.id, sent_at: since..).includes(rule: :gateway, person: [])
      reminders = reminders.select { |reminder| reminder.rule.enabled? && reminder.rule.reminders? }
      return if reminders.empty?

      engine = Accounting::Reminders.new
      items = reminders.uniq { |reminder| [ reminder.rule_id, reminder.person_id, reminder.milestone_key ] }.filter_map do |reminder|
        item_for(engine, reminder)
      end
      return if items.empty?

      AccountingMailer.render_sections(Accounting::ReminderMessage.new(person, items).sections)
    end

    def register(digests = GatherPack::Digests)
      digests.register(KEY, label: "Account reminders", delivery: -> { delivery },
        build: ->(person, since:) {
          html = html_for(person, since: since)
          digests::Section.new(body: html, link: Rails.application.routes.url_helpers.person_accounting_url(person)) if html
        })
    end

    private
      # The reminder as it stands now: nothing once the person has paid or
      # the recipient may no longer see the result.
      def item_for(engine, reminder)
        rule = reminder.rule
        result = rule.results.find_by(person_id: reminder.person_id)
        return if result.nil? || result.value.in?(Accounting::Reminders::SETTLED)

        recipient, guardian, access = engine.recipients(rule, result.person).find { |candidate, _, _| candidate.id == reminder.recipient_id }
        return unless recipient

        milestone = if reminder.milestone_key == AccountingReminder::OVERDUE
          result.detail(:missed)
        else
          Array(result.detail(:milestones)).find { |found| found["key"].to_s == reminder.milestone_key }
        end
        return unless milestone

        Accounting::Reminders::Item.new(rule: rule, result: result, recipient: recipient, guardian: guardian,
          milestone_key: reminder.milestone_key, milestone: milestone, level: engine.level_for(rule, access))
      end
  end
end
