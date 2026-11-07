# "Might be the same person as <name>. Link or keep separate." for the
# registration's managers (Intake::MatchLink).
class Intake::MatchesController < InternalController
  before_action :require_intake_feature
  before_action :set_member

  # POST /registrations/:registration_id/matches/:id/link
  def link
    match = Intake::MatchLink.new(@member).link!
    redirect_back_or_to intake_registration_path(@registration), notice: "Linked to #{match.display_name}."
  rescue Intake::MatchLink::Refused => e
    redirect_back_or_to intake_registration_path(@registration), alert: e.message
  end

  # POST /registrations/:registration_id/matches/:id/keep_separate
  def keep_separate
    Intake::MatchLink.new(@member).keep_separate!
    redirect_back_or_to intake_registration_path(@registration), notice: "Kept separate."
  end

  private

  def require_intake_feature
    redirect_to root_path, notice: "Registration isn't turned on." unless Intake.enabled?
  end

  def set_member
    @registration = authorize policy_scope(Intake::Registration).find(params[:registration_id]), :update?
    @member = Intake::HouseholdMember.where.not(role: :guardian).joins(:entry)
      .where(intake_entries: { registration_id: @registration.id }).find(params[:id])
  end
end
