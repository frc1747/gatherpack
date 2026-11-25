class AddSecretsToGateways < ActiveRecord::Migration[8.1]
  def change
    add_column :gateways, :secrets, :text
  end
end
