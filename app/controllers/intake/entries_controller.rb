# Sends a sign-up's email again (a new link), a few times a day at most.
class Intake::EntriesController < InternalController
  before_action :require_intake_feature

  # POST /registrations/:registration_id/entries/:id/resend
  def resend
    registration = authorize policy_scope(Intake::Registration).find(params[:registration_id]), :resend?
    entry = registration.entries.unverified.find(params[:id])
    store = Intake.rate_limit_store || Rails.cache
    count = store.increment("intake-rate-limit:resend:#{entry.id}", 1, expires_in: 1.day)
    if count && count > Intake.setting(:intake_rate_resend_per_day, 3)
      redirect_back_or_to intake_registration_path(registration), alert: "That sign-up's email was sent again too often today. Try again tomorrow."
    else
      Intake::EntryEmailJob.perform_later(entry.id)
      redirect_back_or_to intake_registration_path(registration), notice: "Sent again."
    end
  end

  private

  def require_intake_feature
    redirect_to root_path, notice: "Registration isn't turned on." unless Intake.enabled?
  end
end
