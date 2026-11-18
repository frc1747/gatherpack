class SendEmailJob < ApplicationJob
  queue_as :default

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
