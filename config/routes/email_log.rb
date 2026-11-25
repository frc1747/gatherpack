# Sent email log (config/initializers/email_log.rb). The controllers check
# the feature switch.
resources :sent_emails, only: :index
resources :gateways, only: [] do
  resource :webhook_events, only: %i[show create], controller: "gateway_webhook_events"
end
