class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include KioskConfinement

  impersonates :user

  # An impersonation ends on its own after this long.
  IMPERSONATION_LIFETIME = 1.hour

  around_action :set_time_zone
  before_action :set_paper_trail_whodunnit
  before_action :check_impersonation
  before_action :confine_kiosk_account
  before_action :check_for_user, unless: :devise_controller?

  def admin?
    current_user&.admin
  end

  def architect?
    current_user&.architect
  end

  def manager?
    current_user&.person&.manager?
  end

  helper_method :admin?, :architect?, :manager?, :kiosk_page?

  rescue_from Pundit::NotAuthorizedError, with: :pundit_not_authorized

  private

  def check_for_user
    unless current_user
      if request.get? && !request.xhr? && request.fullpath != new_user_session_path
        session[:user_return_to] = request.fullpath
      end
      redirect_to new_user_session_path, notice: "You must be logged in to do that"
    end
  end

  def after_sign_up_path_for(resource)
    path = session.delete(:user_return_to) || stored_location_for(resource) || root_path
    Rails.logger.info "[Auth] after_sign_up_path_for: redirecting to \\#{path}"
    path
  end

  def after_sign_in_path_for(resource)
    path = session.delete(:user_return_to) || stored_location_for(resource) || root_path
    Rails.logger.info "[Auth] after_sign_in_path_for: redirecting to \\#{path}"
    path
  end

  # Pretender keeps the impersonated user in the session, so the true user's
  # right to impersonate them is asked again on every request (with the same
  # rule people#impersonate uses), and an impersonation ends once it is older
  # than IMPERSONATION_LIFETIME.
  def check_impersonation
    return if current_user == true_user

    started_at = session[:impersonation_started_at]
    if started_at.nil? || Time.zone.at(started_at) < IMPERSONATION_LIFETIME.ago
      end_impersonation("expired")
      redirect_to root_path, notice: "Your impersonation has ended: it lasts at most #{IMPERSONATION_LIFETIME.inspect}."
    elsif current_user.person.nil? || !PersonPolicy.new(true_user, current_user.person).impersonate?
      end_impersonation("no longer allowed")
      redirect_to root_path, notice: "Your impersonation has ended: you are no longer allowed to impersonate this person."
    end
  end

  # Starting and stopping an impersonation go in the audit log, as an entry
  # for the impersonated login with the true user as whodunnit.
  def begin_impersonation(user)
    impersonate_user(user)
    session[:impersonation_started_at] = Time.current.to_i
    log_impersonation("impersonate", user)
  end

  def end_impersonation(reason)
    user = current_user
    stop_impersonating_user
    session.delete(:impersonation_started_at)
    log_impersonation("stop_impersonating", user, reason) if user != true_user
  end

  def log_impersonation(event, user, reason = nil)
    AuditLog.create!(item: user, event: event, whodunnit: true_user.id)
    Rails.logger.info "[Auth] #{event}: #{true_user.id} as #{user.id}#{" (#{reason})" if reason}"
  end

  def check_for_admin
    redirect_to root_path, notice: "You are not allowed to do that" unless admin?
  end

  def check_for_architect
    redirect_to root_path, notice: "You are not allowed to do that" unless architect?
  end

  def pundit_not_authorized
    redirect_back_or_to root_path, notice: "You are not allowed to do that"
  end

  def set_time_zone(&block)
    Time.use_zone(Settings[:time_zone].presence || "UTC", &block)
  end

  def user_for_paper_trail
    true_user&.id
  end
end
