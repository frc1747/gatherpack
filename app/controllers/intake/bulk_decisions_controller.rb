# POST /teams/:team_id/applications/bulk: approve or deny the selected
# pending applications on a team's page. Approve skips, and names, any row
# it can't take: a checklist the registration waits for that isn't done, a
# team the manager must pick, or an application that is the manager's own or
# a relative's. Deny keeps one reason for all and sends it. Each decision is
# the same as deciding the row on its own (placement, notices, hooks and the
# checklist state kept with it).
class Intake::BulkDecisionsController < InternalController
  before_action :require_intake_feature
  before_action :set_team

  def create
    authorize @team, :applications?
    applications = @team.membership_applications.pending.where(id: Array(params[:application_ids])).includes(:person, :registration).order(:created_at)
    return redirect_to(applications_team_path(@team), alert: "Choose at least one application.") if applications.empty?

    case params[:decision]
    when "approved" then approve(applications)
    when "denied" then deny(applications)
    else redirect_to applications_team_path(@team), alert: "Choose Approve or Deny."
    end
  end

  private

  def require_intake_feature
    redirect_to root_path, notice: "Registration isn't turned on." unless Intake.enabled?
  end

  def set_team
    @team = Team.find(params[:team_id])
  end

  def approve(applications)
    approved = 0
    skipped = applications.filter_map do |application|
      reason = skip_reason(application)
      next "#{application.person.display_name} (#{reason})" if reason

      application.intake_approver = current_user if application.registration
      application.approve!
      approved += 1
      nil
    rescue Intake::ApprovalGate::Blocked, ActiveRecord::RecordInvalid => e
      "#{application.person.display_name} (#{e.message.delete_suffix(".")})"
    end
    finish("Approved #{approved}.", skipped)
  end

  def deny(applications)
    denied = 0
    skipped = applications.filter_map do |application|
      reason = refused(application)
      next "#{application.person.display_name} (#{reason})" if reason

      application.deny!(params[:reason].to_s.strip.presence)
      denied += 1
      nil
    end
    finish("Denied #{denied}.", skipped)
  end

  def finish(notice, skipped)
    flash[:alert] = "Skipped: #{skipped.join("; ")}." if skipped.any?
    redirect_to applications_team_path(@team), notice: notice, status: :see_other
  end

  # Why this person can't decide the application at all.
  def refused(application)
    return "not yours to decide" unless policy(application).update?
    "yours or a relative's" if Intake.enabled? && Intake.own_or_relatives?(current_user.person, application.person)
  end

  def skip_reason(application)
    refused(application) || gate_reason(application) || pick_reason(application)
  end

  def gate_reason(application)
    Intake::ApprovalGate.new(application).reason&.then { "checklist not done" }
  end

  # A required pick can't be made from the list; it's made row by row.
  def pick_reason(application)
    return unless Intake.enabled? && application.registration
    "choose a team" if Intake::Placement.new(application: application).pick_required?
  end
end
