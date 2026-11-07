# Included into MembershipApplicationsController from
# config/initializers/intake.rb. Before an approval or denial of an
# application from a registration, it takes the manager's pick-one team
# (refusing the approval when the registration requires one) and the
# denial's reason.
module Intake::ApplicationDecisions
  extend ActiveSupport::Concern

  included do
    before_action :intake_decision_details, only: :update
  end

  private

  def intake_decision_details
    application = @membership_application
    return unless Intake.enabled? && application&.registration && application.pending?

    case params[:status]
    when "approved"
      placement = Intake::Placement.new(application: application, pick_team: Team.find_by(id: params[:pick_team_id].presence))
      pick = placement.pick_teams.find_by(id: placement.pick_team&.id)
      if placement.pick_required? && pick.nil?
        redirect_back_or_to applications_team_path(application.team), alert: "Choose a team for #{application.person.first_name}."
      else
        application.intake_pick_team = pick
      end
    when "denied"
      application.reviewer_notes = params[:reason].to_s.strip.presence || application.reviewer_notes
    end
  end
end
