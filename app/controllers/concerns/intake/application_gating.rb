# Included into MembershipApplicationsController from
# config/initializers/intake_checklist.rb. An approval waits while the
# registration gates it on a checklist the applicant hasn't finished.
module Intake::ApplicationGating
  extend ActiveSupport::Concern

  included do
    before_action :intake_check_gate, only: :update
  end

  private

  def intake_check_gate
    application = @membership_application
    return unless params[:status] == "approved" && application&.pending? && application.registration

    reason = Intake::ApprovalGate.new(application).reason
    redirect_back_or_to applications_team_path(application.team), alert: reason if reason
  end
end
