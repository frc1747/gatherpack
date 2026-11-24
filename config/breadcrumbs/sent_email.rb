crumb :sent_emails do
  link "Sent email", sent_emails_path
  parent :setup
end

crumb :gateway_webhook_events do |gateway|
  link "Update webhook events", gateway_webhook_events_path(gateway)
  parent gateway
end
