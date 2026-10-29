# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
#
# :token covers gateway API tokens, OAuth tokens and kiosk card values (a
# "token" key filters its whole hash, so token[value] goes too). Doorkeeper
# filters the OAuth code itself, but only that exact name, not the PKCE
# code_verifier.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc, :code_verifier
]
