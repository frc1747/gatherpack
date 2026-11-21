# Base controller for the jobs dashboard (Mission Control, mounted at /jobs;
# see config/initializers/mission_control.rb). The dashboard shows job
# arguments and can retry, discard and dispatch jobs, so it is for admins.
# Its shared HTTP basic password still applies on top.
class JobsDashboardController < InternalController
  before_action :authorize_jobs_dashboard

  private

  # Jobs aren't records, so there is nothing to scope; authorize covers
  # every page.
  def authorize_jobs_dashboard
    authorize :jobs_dashboard, :show?
    skip_policy_scope
  end

  # Inside the engine, root_path is the dashboard's own.
  def pundit_not_authorized
    redirect_to main_app.root_path, notice: "You are not allowed to do that"
  end
end
