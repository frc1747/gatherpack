# Sample data for feature/email-log (fork/sample_data/features/email-log.rb).
#
# Six sent emails in every state the Sent email screen shows (Setup → Email →
# Sent email): delivered and clicked, delivered with only a scanner's click
# (counted, shown as not clicked), sent and not yet reported, bounced,
# marked as spam, and failed. Two are about the Spring Workday event, so the
# About filter has something to pick. The rows have no gateway: loading never
# creates a sending gateway, sends anything or calls a mail service.
Hbr::SampleData.feature "feature/email-log" do |s|
  s.enable_feature :email_log

  workday = Event.find_by!(name: "Spring Workday")
  ben = s.person("Ben")
  chloe = s.person("Chloe")
  dan = s.person("Dan")
  ava = s.person("Ava")
  mara = s.login(:manager)

  log = lambda do |provider_id, attrs|
    s.upsert!(SentEmail, { provider_message_id: provider_id }, { gateway: nil, click_count: 0 }.merge(attrs))
  end

  delivered = s.clock.hours_ago(26)
  log.call("sample-email-1", person: ben, address: "ben@example.com", subject: "Spring Workday: you're signed up",
    about: workday, status: "delivered", sent_at: delivered - 4, delivered_at: delivered,
    created_at: delivered - 5, first_clicked_at: delivered + 7 * 60, click_count: 2, first_clicked_url: "https://example.com/events")

  scanned = s.clock.hours_ago(20)
  log.call("sample-email-2", person: chloe, address: "chloe@example.com", subject: "Spring Workday: you're signed up",
    about: workday, status: "delivered", sent_at: scanned - 3, delivered_at: scanned,
    created_at: scanned - 4, first_clicked_at: scanned + 2, click_count: 1, first_clicked_url: "https://example.com/events")

  log.call("sample-email-3", person: mara, address: mara.user.email, subject: "Weekly summary",
    status: "sent", sent_at: s.clock.hours_ago(1), created_at: s.clock.hours_ago(1) - 2)

  bounced = s.clock.days_ago(3, hour: 18)
  log.call("sample-email-4", person: dan, address: "dan.old-address@example.com", subject: "Weekly summary",
    status: "bounced", sent_at: bounced, created_at: bounced - 2, problem_at: bounced + 30, problem_detail: "The mailbox does not exist")

  spam = s.clock.days_ago(5, hour: 18)
  log.call("sample-email-5", person: ava, address: "ava@example.com", subject: "Weekly summary",
    status: "complained", sent_at: spam, created_at: spam - 2, delivered_at: spam + 5, problem_at: s.clock.days_ago(4, hour: 8))

  failed = s.clock.days_ago(2, hour: 12)
  log.call("sample-email-6", person: nil, address: "volunteer@example.com", subject: "Reset your password",
    status: "failed", sent_at: failed, created_at: failed - 2, problem_at: failed + 1, problem_detail: "The sending service refused the message: domain not verified")

  s.report "6 sent emails: delivered and clicked, scanner click only, sent, bounced, marked as spam, failed"
  s.expect("Ben's email shows a link click") { SentEmail.find_by!(provider_message_id: "sample-email-1").link_clicked_at.present? }
  s.expect("Chloe's scanner click isn't shown") { SentEmail.find_by!(provider_message_id: "sample-email-2").link_clicked_at.nil? }
  s.expect("listed newest first: the sent one, then Chloe's") { SentEmail.newest_first.where("provider_message_id LIKE 'sample-email-%'").limit(2).pluck(:provider_message_id) == %w[sample-email-3 sample-email-2] }
  s.expect("one of each problem") { %w[bounced complained failed].all? { |status| SentEmail.exists?(status: status) } }
end
