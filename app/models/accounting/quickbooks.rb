# QuickBooks Online as an accounting source. Everything that knows
# QuickBooks' API or field names lives under this namespace and in
# Gateway::QuickbooksGateway.
module Accounting::Quickbooks
  AUTHORIZE_URL = "https://appcenter.intuit.com/connect/oauth2".freeze
  TOKEN_URL = "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer".freeze
  REVOKE_URL = "https://developer.api.intuit.com/v2/oauth2/tokens/revoke".freeze
  SCOPE = "com.intuit.quickbooks.accounting".freeze
  MINOR_VERSION = "75".freeze

  API_HOSTS = {
    "sandbox" => "https://sandbox-quickbooks.api.intuit.com",
    "production" => "https://quickbooks.api.intuit.com"
  }.freeze

  # Where people open a record in QuickBooks.
  APP_HOSTS = {
    "sandbox" => "https://app.sandbox.qbo.intuit.com",
    "production" => "https://app.qbo.intuit.com"
  }.freeze
end
