# A source's sign-in tokens. They rotate hourly, so they live here rather
# than in the gateway's secrets, where each refresh would update the
# gateway, fire its hooks and race with edits. Not hooked and not audited.
class AccountingCredential < ApplicationRecord
  has_neat_id :acred

  belongs_to :gateway

  encrypts :access_token, :refresh_token

  def access_token_expires_within?(duration)
    access_token.blank? || access_token_expires_at.blank? || access_token_expires_at <= duration.from_now
  end
end
