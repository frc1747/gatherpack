class CreateAccountingCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_credentials, id: :uuid do |t|
      t.references :gateway, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :access_token
      t.datetime :access_token_expires_at
      t.text :refresh_token
      t.datetime :refresh_token_expires_at

      t.timestamps
    end
  end
end
