class SendEmailJob < ApplicationJob
  queue_as :default

  # One email at a time, so a burst of notices stays under the sending
  # service's rate limit (Resend allows 10 requests a second). Waiting jobs
  # don't hold a worker thread. The retry catches any send still refused.
  limits_concurrency to: 1, key: "send_email"
  retry_on Gateway::RateLimited, wait: :polynomially_longer, attempts: 10

  def perform(gateway, address, subject, body)
    if gateway
      gateway.send_message(address, subject, body)
    else
      puts "No email gateway configured. Cannot send email."
      puts Gateway.registry.inspect
    end
  end
end
