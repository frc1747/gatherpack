# Works out and sends the day's account reminders (spec: native reminders
# on the rule). A balance rule with reminder settings reminds the people it
# applies to who haven't met a milestone yet, the given number of days
# before it, and while they're overdue, every given number of days. The
# milestones are the ones the person's result was worked out against, so a
# person on a payment plan is reminded before the plan's.
#
# Reminders go to the person, their guardians, or both, as the rule says,
# and only to recipients who meet the rule's read_permission for the
# person in that role: leaders are never recipients. What a reminder may
# say is the rule's reminder_level, held back to the name and status for a
# recipient who may not see amounts.
#
# One email per recipient a day, however many rules and people it covers
# (Accounting::ReminderMessage, AccountingMailer); AccountingReminder logs
# each so the same milestone is never reminded twice and overdue ones are
# spaced. Where summaries are merged (Accounting::ReminderDigest), people
# who chose the summary get them there instead.
class Accounting::Reminders
  LEVELS = AccountingRule::REMINDER_LEVELS
  # Results that have nothing to remind about.
  SETTLED = %w[ paid not_invoiced ].freeze

  # One reminder about one person to one recipient. milestone is the
  # result's milestone hash (name, due_on, catch_up_cents); level what it
  # may say to this recipient.
  Item = Data.define(:rule, :result, :recipient, :guardian, :milestone_key, :milestone, :level) do
    def person = result.person
    def overdue? = milestone_key == AccountingReminder::OVERDUE
    def guardian? = guardian
  end

  attr_reader :today

  def initialize(today: Date.current)
    @today = today
  end

  def self.enabled?
    Accounting.enabled?
  end

  # Every reminder due today, across rules.
  def items
    @items ||= rules.flat_map { |rule| items_for(rule) }
  end

  # Sends the day's reminders: one email per recipient, leaving out anyone
  # already sent an account reminder today. Returns the messages emailed.
  def send!
    return [] unless self.class.enabled?

    sent_today = AccountingReminder.where(sent_at: today.in_time_zone.all_day).distinct.pluck(:recipient_id).to_set
    now = Time.current
    items.reject { |item| sent_today.include?(item.recipient.id) }.group_by { |item| item.recipient.id }.filter_map do |_, theirs|
      recipient = theirs.first.recipient
      route = Accounting::ReminderDigest.route(recipient)
      next if route == :off

      message = Accounting::ReminderMessage.new(recipient, theirs)
      deliver(message) if route == :email
      log(theirs, now)
      message if route == :email
    end
  end

  # The reminders about a person due today for the given rule (or every
  # rule), to everyone they'd go to.
  def items_for(rule, person_ids: nil)
    return [] unless rule.enabled? && rule.reminders?

    results = rule.results.where.not(value: SETTLED + [ AccountingRule::ERROR ]).where(person_id: rule.people.select(:id)).includes(:person)
    results = results.where(person_id: person_ids) if person_ids
    results = results.to_a
    return [] if results.empty?

    sent = rule.reminders.where(person_id: results.map(&:person_id)).group(:person_id, :recipient_id, :milestone_key).maximum(:sent_at)
    results.flat_map do |result|
      due = due_milestones(rule, result)
      next [] if due.empty?

      recipients(rule, result.person).flat_map do |recipient, guardian, access|
        due.filter_map do |key, milestone|
          last = sent[[ result.person_id, recipient.id, key ]]
          next unless due_again?(rule, key, last)

          Item.new(rule: rule, result: result, recipient: recipient, guardian: guardian, milestone_key: key, milestone: milestone,
            level: level_for(rule, access))
        end
      end
    end
  end

  # The people a reminder about the person goes to, as [recipient,
  # guardian?, access]: only those with an email who meet the rule's
  # read_permission for the person in that role.
  def recipients(rule, person)
    candidates = []
    candidates << [ person, false ] if rule.remind_person?
    person.guardians.each { |guardian| candidates << [ guardian, true ] } if rule.remind_guardians?
    candidates.uniq { |recipient, _| recipient.id }.filter_map do |recipient, guardian|
      next if recipient.user&.email.blank?
      next unless AudienceLevels.reaches?(rule.read_permission, guardian ? :guardian : :subject)

      access = Accounting::RuleAccess.new(recipient, person, rule)
      next unless access.can_read? && access.component?(guardian ? :guardian : :subject)

      [ recipient, guardian, access ]
    end
  end

  # What a reminder may say to a recipient: the rule's level, but amounts
  # and pay links only to those who may see amounts.
  def level_for(rule, access)
    level = rule.reminder_level.presence_in(LEVELS) || "name_only"
    level == "everything" && !access.can_see_amounts? ? "name_only" : level
  end

  private
    def rules
      AccountingRule.enabled.where(kind: "balance").includes(:gateway).ordered.select(&:reminders?)
    end

    # [key, milestone] for each milestone the person is reminded about
    # today: those not yet met whose date is within the rule's days before,
    # and while overdue, the missed one.
    def due_milestones(rule, result)
      due = []
      if rule.remind_days_before.present?
        days = rule.remind_days_before.to_i
        Array(result.detail(:milestones)).each do |milestone|
          date = parse_date(milestone["due_on"])
          next if milestone["met"] || date.nil?

          due << [ milestone["key"].to_s, milestone ] if today.between?(date - days, date)
        end
      end
      if rule.overdue_every_days.present? && result.value == "overdue" && (missed = result.detail(:missed))
        due << [ AccountingReminder::OVERDUE, missed ]
      end
      due
    end

    # A milestone is reminded once; overdue reminders every so many days.
    def due_again?(rule, key, last_sent)
      return true unless last_sent
      return false unless key == AccountingReminder::OVERDUE

      last_sent.to_date <= today - rule.overdue_every_days.to_i
    end

    def deliver(message)
      subject, body = AccountingMailer.render(message.payload)
      SendEmailJob.perform_later(Gateway[:email_sending], message.email, subject, body)
    end

    def log(items, now)
      AccountingReminder.insert_all!(items.map do |item|
        { rule_id: item.rule.id, person_id: item.person.id, recipient_id: item.recipient.id, milestone_key: item.milestone_key,
          sent_at: now, created_at: now, updated_at: now }
      end)
    end

    def parse_date(value)
      value.is_a?(Date) ? value : Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
end
