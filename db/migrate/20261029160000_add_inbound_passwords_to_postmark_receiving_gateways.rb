class AddInboundPasswordsToPostmarkReceivingGateways < ActiveRecord::Migration[8.1]
  # Inbound mail is refused without HTTP basic auth now. Give existing
  # Postmark receiving gateways a password; the inbound URL in Postmark has
  # to be updated with it (see the gateway page).
  class Gateway < ActiveRecord::Base
    self.table_name = "gateways"
    self.inheritance_column = nil
  end

  def up
    Gateway.where(type: "Gateway::PostmarkReceivingGateway").find_each do |gateway|
      configuration = gateway.configuration || {}
      next if configuration["inbound_password"].present?

      gateway.update_columns(configuration: configuration.merge("inbound_password" => SecureRandom.alphanumeric(32)))
    end
  end

  def down
    Gateway.where(type: "Gateway::PostmarkReceivingGateway").find_each do |gateway|
      gateway.update_columns(configuration: (gateway.configuration || {}).except("inbound_password"))
    end
  end
end
