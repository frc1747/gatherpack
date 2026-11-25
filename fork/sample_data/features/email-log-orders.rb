# Sample data for feature/email-log-orders (fork/sample_data/features/email-log-orders.rb),
# loaded after orders and email-log.
#
# The Pressure washer request (Henry approved, waiting on the Treasurer)
# shows Approval emails on its page: Henry was emailed for the Approval step
# and clicked the link before approving; Ruby was emailed for the Treasurer
# step after that and hasn't clicked yet. The rows have no gateway: loading
# sends nothing.
Hbr::SampleData.feature "feature/email-log-orders" do |s|
  s.enable_feature :email_log

  washer = OrderRequest.find_by!(title: "Pressure washer")
  henry = s.person("Henry")
  ruby = s.person("Ruby")
  approved_at = washer.active_approvals.find { |approval| approval.step_key == "approval" && approval.approved? }.created_at

  log = lambda do |provider_id, attrs|
    s.upsert!(SentEmail, { provider_message_id: provider_id }, { gateway: nil, click_count: 0, about: washer }.merge(attrs))
  end

  henry_sent = approved_at - 3 * 3600
  log.call("sample-order-email-1", person: henry, address: henry.user&.email || "henry@example.com",
    subject: "Northwind - To approve: Pressure washer", status: "delivered", sent_at: henry_sent, created_at: henry_sent - 2,
    delivered_at: henry_sent + 3, first_clicked_at: henry_sent + 7 * 60, click_count: 1, first_clicked_url: "https://example.com/orders/requests")

  ruby_sent = approved_at + 5
  log.call("sample-order-email-2", person: ruby, address: ruby.user&.email || "ruby@example.com",
    subject: "Northwind - To approve: Pressure washer", status: "delivered", sent_at: ruby_sent, created_at: ruby_sent - 2,
    delivered_at: ruby_sent + 3)

  s.report "2 approval emails on Pressure washer: Henry (link clicked), Ruby (not clicked yet)"
  s.expect("Pressure washer lists Henry under Approval and Ruby under Treasurer") do
    steps = EmailLog::OrderRequestEmails.new(washer.reload).steps
    steps.map { |step| [ step.step.key, step.approvers.map(&:person) ] } == [ [ "approval", [ henry ] ], [ "treasurer", [ ruby ] ] ]
  end
end
