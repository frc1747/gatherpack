require "test_helper"
require_relative "../../support/accounting_rules_world"

class Accounting::RemindersTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include AccountingRulesWorld

  DEPOSIT = Date.new(2026, 10, 10)

  setup do
    @team = create_rule_team("Robotics")
    @laura = create_rule_person("Laura", "Callahan", admin: true)
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @margaret = create_rule_person("Margaret", "Peacock")
    add_guardian(@margaret, @nancy, by: @laura)
    @andrew = create_rule_person("Andrew", "Fuller", team: @team, manager: true)
    @janet = create_rule_person("Janet", "Leverling", team: @team, customer: "60")
    add_charge("58", "I1", total: 40_000, balance: 40_000, label: "Invoice 1042 · Dues", pay_url: "https://pay.example.com/1042",
      description: "Hardship note")
    add_charge("60", "I2", total: 40_000, balance: 10_000, label: "Invoice 1043 · Dues")
    @rule = create_rule(read_permission: "family", amount_permission: "family", team: @team, show_pay_links: true,
      remind_days_before: 3, overdue_every_days: 7, remind_to: "both", reminder_level: "everything",
      milestones: [ { name: "Deposit", due_on: DEPOSIT, balance_at_most_percent: 50 },
                    { name: "Paid in full", due_on: Date.new(2027, 1, 15), balance_at_most_cents: 0 } ])
  end

  test "sent N days before a milestone only to people not meeting it, never to leaders" do
    emails = send_on(DEPOSIT - 4)
    assert_empty emails

    emails = send_on(DEPOSIT - 3)
    assert_equal [ @margaret.user.email, @nancy.user.email ].sort, emails.keys.sort
    assert_not_includes emails.keys, @andrew.user.email
    assert_not_includes emails.keys, @janet.user.email, "Janet has met the deposit"
    subject, body = emails[@nancy.user.email]
    assert_match "Reminder: 2027 Membership Dues", subject
    assert_match "Deposit is due", body
    assert_match "$200.00 to meet Deposit", body
    assert_match "https://pay.example.com/1042", body
    assert_no_match "Hardship", body
    assert_match "2027 Membership Dues: Nancy Davolio", emails[@margaret.user.email].last
  end

  test "no repeat for the same milestone, and overdue ones every N days" do
    assert_equal 2, send_on(DEPOSIT - 3).size
    assert_empty send_on(DEPOSIT - 2)

    overdue = DEPOSIT + 1
    emails = send_on(overdue)
    assert_equal 2, emails.size
    assert_match "Overdue: Deposit was due", emails[@nancy.user.email].last
    assert_empty send_on(overdue + 3)
    assert_empty send_on(overdue + 6)
    assert_equal 2, send_on(overdue + 7).size
    assert_equal 2, @rule.reminders.where(milestone_key: "overdue", recipient: @nancy).count
  end

  test "guardians only when the result level includes them" do
    @rule.update!(read_permission: "self_and_leaders", amount_permission: "self")

    emails = send_on(DEPOSIT - 3)

    assert_equal [ @nancy.user.email ], emails.keys
  end

  test "guardians or the person alone, as the rule says" do
    @rule.update!(remind_to: "guardians")
    assert_equal [ @margaret.user.email ], send_on(DEPOSIT - 3).keys

    @rule.reminders.delete_all
    @rule.update!(remind_to: "person")
    assert_equal [ @nancy.user.email ], send_on(DEPOSIT - 3).keys
  end

  test "amounts and pay links only to recipients who may see amounts; anyone else gets the name and status" do
    @rule.update!(amount_permission: "self")

    emails = send_on(DEPOSIT - 3)

    assert_match "$200.00 to meet Deposit", emails[@nancy.user.email].last
    guardian = emails[@margaret.user.email].last
    assert_match "Deposit is due", guardian
    assert_match "Not yet paid", guardian
    assert_no_match "$", guardian
    assert_no_match "pay.example.com", guardian
  end

  test "a name-only reminder names the rule, status and milestone, without amounts" do
    @rule.update!(reminder_level: "name_only")

    _, body = send_on(DEPOSIT - 3)[@nancy.user.email]

    assert_match "2027 Membership Dues", body
    assert_match "Not yet paid. Deposit is due", body
    assert_no_match "$", body
    assert_no_match "Pay online", body
  end

  test "sign_in says nothing about the account" do
    @rule.update!(reminder_level: "sign_in")

    emails = send_on(DEPOSIT - 3)

    subject, body = emails[@nancy.user.email]
    assert_match "Account reminder", subject
    assert_match "You have an account update. Sign in to see it.", body
    [ "Dues", "Deposit", "Not yet paid", "$", "pay.example.com" ].each { |word| assert_no_match word, body }
    assert_match "Nancy has an account update", emails[@margaret.user.email].last
    assert_no_match "Deposit", emails[@margaret.user.email].last
  end

  test "one email per recipient a day, however many rules remind them" do
    create_rule("Travel fee 2027", read_permission: "family", amount_permission: "family", team: @team,
      remind_days_before: 3, milestones: [ { name: "Trip deposit", due_on: DEPOSIT, balance_at_most_cents: 0 } ])
    later = create_rule("Uniform 2027", read_permission: "family", amount_permission: "family", team: @team, enabled: false,
      remind_days_before: 3, milestones: [ { name: "Uniform", due_on: DEPOSIT, balance_at_most_cents: 0 } ])

    emails = send_on(DEPOSIT - 3)

    assert_equal [ @janet, @margaret, @nancy ].map { |person| person.user.email }.sort, emails.keys.sort
    subject, body = emails[@nancy.user.email]
    assert_match "Account reminder", subject
    assert_match "Deposit is due", body
    assert_match "Trip deposit is due", body

    later.update!(enabled: true)
    assert_empty send_on(DEPOSIT - 3), "nobody gets a second account email the same day"
    assert_equal 3, send_on(DEPOSIT - 2).size, "the turned-on rule's reminder goes the next day"
  end

  test "a person on a plan is reminded before the plan's milestones" do
    @rule.person_milestones.create!(person: @nancy, name: "First payment", due_on: DEPOSIT + 10, balance_at_most_cents: 30_000)
    @rule.person_milestones.create!(person: @nancy, name: "Last payment", due_on: Date.new(2027, 3, 1), balance_at_most_cents: 0)

    assert_empty send_on(DEPOSIT - 3).slice(@nancy.user.email, @margaret.user.email)
    emails = send_on(DEPOSIT + 7)
    assert_match "First payment is due", emails[@nancy.user.email].last
    assert_no_match "Deposit", emails[@nancy.user.email].last
    assert_match "$100.00 to meet First payment", emails[@margaret.user.email].last
  end

  test "people without a login or email aren't sent anything" do
    @margaret.user.destroy!

    assert_equal [ @nancy.user.email ], send_on(DEPOSIT - 3).keys
  end

  test "nothing is sent while the feature is off, or for a turned-off rule" do
    evaluate(@rule, today: DEPOSIT - 3)

    with_accounting(false) do
      assert_no_enqueued_jobs(only: SendEmailJob) { Accounting::ReminderJob.perform_now }
    end
    @rule.update!(enabled: false)
    with_accounting do
      assert_no_enqueued_jobs(only: SendEmailJob) { Accounting::Reminders.new(today: DEPOSIT - 3).send! }
    end
    assert_equal 0, AccountingReminder.count
  end

  test "the daily job sends today's reminders" do
    travel_to DEPOSIT - 3 do
      evaluate(@rule)
      with_accounting do
        assert_enqueued_jobs(2, only: SendEmailJob) { Accounting::ReminderJob.perform_now }
      end
    end
  end

  test "with summaries merged, each person's choice is respected" do
    with_fake_digests(@margaret.id => :daily, @nancy.id => :each) do
      emails = send_on(DEPOSIT - 3)

      assert_equal [ @nancy.user.email ], emails.keys
      assert_equal 1, @rule.reminders.where(recipient: @margaret).count
      with_accounting do
        html = Accounting::ReminderDigest.html_for(@margaret, since: (DEPOSIT - 3).beginning_of_day)
        assert_match "Deposit is due", html
        assert_match "Nancy Davolio", html
        assert_nil Accounting::ReminderDigest.html_for(@nancy, since: (DEPOSIT - 3).beginning_of_day), "Nancy had the email"
      end
    end

    with_fake_digests(@margaret.id => :off, @nancy.id => :off) do
      @rule.reminders.delete_all
      assert_empty send_on(DEPOSIT - 3)
      assert_equal 0, @rule.reminders.count
    end
  end

  test "the rule's reminder settings are checked and kept by Duplicate, without the reminder history" do
    assert_not @rule.tap { |rule| rule.remind_days_before = "-1" }.valid?
    @rule.remind_days_before = "abc"
    assert_not @rule.valid?
    @rule.remind_days_before = "3"
    @rule.remind_to = "leaders"
    assert_not @rule.valid?
    @rule.reload
    send_on(DEPOSIT - 3)

    copy = @rule.duplicate!

    assert_equal [ 3, 7, "both", "everything" ], copy.attributes.values_at("settings").first.values_at("remind_days_before", "overdue_every_days", "remind_to", "reminder_level")
    assert_equal 0, copy.reminders.count
    assert_equal 2, @rule.reminders.count
  end

  private
    # Evaluates the rule as of the day and sends that day's reminders.
    # { email => [subject, body] }
    def send_on(day)
      AccountingRule.enabled.each { |rule| evaluate(rule, today: day) }
      clear_enqueued_jobs
      travel_to(day.in_time_zone.change(hour: 8)) do
        with_accounting { Accounting::Reminders.new(today: day).send! }
      end
      enqueued_jobs.select { |job| job[:job] == SendEmailJob }.to_h { |job| [ job[:args][1], job[:args][2..3] ] }
    end

    # A stand-in for the summaries seam (feature/digests), which this
    # branch doesn't carry: each person's delivery choice.
    def with_fake_digests(choices)
      digests = Module.new do
        define_singleton_method(:handles?) { |key| key == :accounting }
        define_singleton_method(:delivery_for) { |_key, person| choices.fetch(person.id, :each) }
      end
      GatherPack.const_set(:Digests, digests)
      yield
    ensure
      GatherPack.send(:remove_const, :Digests) if GatherPack.const_defined?(:Digests, false)
    end
end
