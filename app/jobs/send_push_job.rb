class SendPushJob < ApplicationJob
  queue_as :default

  NETWORK_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, SocketError, EOFError, OpenSSL::SSL::SSLError,
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT ].freeze

  # The device or gateway went away after this was queued.
  discard_on ActiveJob::DeserializationError

  # Anything else the push service refuses won't go better a second time.
  discard_on WebPush::ResponseError do |job, error|
    Rails.logger.warn("SendPushJob #{job.job_id} refused: #{error.class}")
  end

  retry_on WebPush::PushServiceError, WebPush::TooManyRequests, *NETWORK_ERRORS, wait: :polynomially_longer, attempts: 4 do |job, error|
    Rails.logger.warn("SendPushJob #{job.job_id} gave up: #{error.class}")
  end

  def perform(gateway, subscription, title, path)
    return unless GatherPack::PushChannel.available?

    gateway.send_message(subscription, title, path)
    subscription.update_column(:last_sent_at, Time.current)
  rescue WebPush::InvalidSubscription, WebPush::ExpiredSubscription
    subscription.destroy
  end
end
