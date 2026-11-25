# The realm id and company name of a QuickBooks source move from its plain
# configuration into its encrypted secrets, which the audit log never holds.
class MoveQuickbooksRealmIntoSecrets < ActiveRecord::Migration[8.1]
  KEYS = %w[ realm_id company_name ].freeze

  class MigrationGateway < ActiveRecord::Base
    self.table_name = "gateways"
    self.inheritance_column = nil
    store :secrets, coder: JSON
    encrypts :secrets
  end

  def up
    move(:configuration, :secrets)
  end

  def down
    move(:secrets, :configuration)
  end

  private
    def move(from, to)
      MigrationGateway.reset_column_information
      MigrationGateway.where(type: "Gateway::QuickbooksGateway").find_each do |gateway|
        source = (gateway.public_send(from) || {}).to_h.stringify_keys
        next unless KEYS.any? { |key| source.key?(key) }

        gateway.public_send("#{from}=", source.except(*KEYS))
        gateway.public_send("#{to}=", (gateway.public_send(to) || {}).to_h.stringify_keys.merge(source.slice(*KEYS).compact_blank))
        gateway.save!
      rescue ActiveRecord::Encryption::Errors::Decryption
        say "Gateway #{gateway.id}: its secrets can't be decrypted; connect it again"
      end
    end
end
