# A random token per login, folded into what Devise checks a session or
# remember-me cookie against (User#authenticatable_salt). Signing out
# replaces it, so copies of the cookies stop working. Each existing login
# gets its own token, which signs everyone out once.
class AddSessionTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :session_token, :string, null: false, default: -> { "gen_random_uuid()::text" }
  end
end
