# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri    :self
    policy.object_src  :none
    policy.frame_ancestors :self
    # Scripts from other hosts (Popper, Font Awesome) carry the nonce.
    policy.script_src  :self
    # Inline style attributes and the theme's <style> block are used throughout.
    policy.style_src   :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.font_src    :self, :data, "https://fonts.gstatic.com"
    # Avatars, uploads and photo capture use data: and blob: URLs.
    policy.img_src     :self, :https, :data, :blob
    policy.media_src   :self, :blob
    # The icon picker searches the Font Awesome API.
    policy.connect_src :self, "https://api.fontawesome.com"
    policy.worker_src  :self
    policy.manifest_src :self
  end

  # A fresh random nonce per response for the importmap and inline scripts.
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Report violations in the browser console without enforcing the policy.
  config.content_security_policy_report_only = true
end
