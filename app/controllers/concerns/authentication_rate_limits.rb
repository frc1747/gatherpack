# Throttles the forms that take an account's email from anyone: sign-in,
# password reset, unlock and sign-up. Each is limited per client IP and per
# email, so passwords can't be guessed at speed from one address, switching
# addresses doesn't get around the limit for one account, and nobody can
# flood a member's inbox with mail. See config/initializers/devise_rate_limits.rb.
module AuthenticationRateLimits
  extend ActiveSupport::Concern

  class << self
    # Where the counts are kept: Rails.cache unless set. The test environment's
    # cache is a null store, so tests that need the limits set a memory store.
    attr_accessor :store

    def increment(...)
      (store || Rails.cache).increment(...)
    end
  end

  class_methods do
    def rate_limit_authentication(per_ip:, per_email:)
      rate_limit to: per_ip[:to], within: per_ip[:within], only: :create, name: "ip",
        store: AuthenticationRateLimits, with: :authentication_rate_limited
      rate_limit to: per_email[:to], within: per_email[:within], only: :create, name: "email",
        by: :authentication_rate_limit_email, if: -> { authentication_rate_limit_email.present? },
        store: AuthenticationRateLimits, with: :authentication_rate_limited
    end

    # Limits a form that checks the signed-in user's current password, per
    # signed-in user, so a copied session can't be used to guess it.
    def rate_limit_current_password(**options)
      rate_limit to: 10, within: 15.minutes, only: :update, name: "current_password", by: -> { true_user.id },
        store: AuthenticationRateLimits, with: :authentication_rate_limited, **options
    end
  end

  private

  def authentication_rate_limit_email
    fields = params[resource_name]
    fields.is_a?(ActionController::Parameters) ? fields[:email].to_s.strip.downcase : ""
  end

  def authentication_rate_limited
    flash.now[:alert] = "Too many attempts. Please wait a few minutes and try again."
    render html: "", layout: true, status: :too_many_requests
  end
end
