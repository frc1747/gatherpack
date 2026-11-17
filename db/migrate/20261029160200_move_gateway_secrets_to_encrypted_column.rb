class MoveGatewaySecretsToEncryptedColumn < ActiveRecord::Migration[8.1]
  # API keys, tokens and passwords move out of the plain configuration column
  # into the encrypted secrets column. Kept here rather than read from the
  # models so the migration doesn't change when they do.
  SECRET_FIELDS = {
    "Gateway::StripeGateway" => %w[secret_key secret],
    "Gateway::ResendSendingGateway" => %w[api_token secret],
    "Gateway::PostmarkSendingGateway" => %w[api_token],
    "Gateway::PostmarkReceivingGateway" => %w[server_token inbound_password],
    "Gateway::SmtpSendingGateway" => %w[password]
  }.freeze

  class Gateway < ActiveRecord::Base
    self.table_name = "gateways"
    self.inheritance_column = nil

    serialize :secrets, coder: JSON
    encrypts :secrets
  end

  def up
    Gateway.reset_column_information

    Gateway.where(type: SECRET_FIELDS.keys).find_each do |gateway|
      fields = SECRET_FIELDS.fetch(gateway.type)
      configuration = gateway.configuration || {}
      secrets = (gateway.secrets || {}).merge(configuration.slice(*fields))

      gateway.update_columns(configuration: configuration.except(*fields), secrets: secrets)
    end
  end

  def down
    Gateway.reset_column_information

    Gateway.where.not(secrets: nil).find_each do |gateway|
      gateway.update_columns(configuration: (gateway.configuration || {}).merge(gateway.secrets || {}), secrets: nil)
    end
  end
end
