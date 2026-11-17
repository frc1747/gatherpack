# Staff screens for registrations: the list, setup (dates, teams, placement
# lists), and the entries screen (counts by day, unfinished sign-ups, Delete
# selected, Close now).
class Intake::RegistrationsController < InternalController
  before_action :require_intake_feature
  before_action :set_team, only: %i[index new]
  before_action :set_registration, only: %i[show edit update destroy copy close destroy_entries waiting]

  # GET /registrations or /teams/:team_id/registrations
  def index
    authorize Intake::Registration
    registrations = policy_scope(Intake::Registration).includes(:team).order(opens_at: :desc)
    registrations = registrations.where(team: @team) if @team
    registrations = registrations.not_archived unless params[:archived] == "1"
    @registrations = registrations
  end

  # GET /registrations/:id
  def show
    entries = @registration.entries
    @entries_by_day = entries.counts_by_day
    @verified_by_day = entries.verified.counts_by_day
    @unverified_entries = @registration.unverified_entries.where(person_id: nil).order(created_at: :desc)
    @application_counts = @registration.membership_applications.group(:status).count
  end

  # GET /registrations/new or /teams/:team_id/registrations/new
  def new
    @registration = Intake::Registration.new(team: @team, opens_at: Time.current.beginning_of_hour)
    authorize @registration, :new?
  end

  # GET /registrations/:id/copy
  def copy
    @registration = @registration.copy
    render :new
  end

  # POST /registrations
  def create
    @registration = Intake::Registration.new(registration_params.merge(created_by: current_user.person))
    authorize @registration
    if @registration.save
      redirect_to intake_registration_path(@registration), notice: "Registration created."
    else
      render :new, status: :unprocessable_content
    end
  end

  # GET /registrations/:id/edit
  def edit
  end

  # PATCH /registrations/:id
  def update
    @registration.assign_attributes(registration_params)
    authorize @registration
    if @registration.save
      redirect_to intake_registration_path(@registration), notice: "Registration saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /registrations/:id
  def destroy
    @registration.destroy!
    redirect_to intake_registrations_path, notice: "Registration deleted.", status: :see_other
  end

  # PATCH /registrations/:id/close
  def close
    # The "closed" hook fires from Intake::RegistrationDatesJob, once.
    @registration.update!(closes_at: Time.current) unless @registration.closed?
    redirect_to intake_registration_path(@registration), notice: "Registration closed."
  end

  # DELETE /registrations/:id/entries
  def destroy_entries
    count = @registration.entries.unverified.where(person_id: nil, id: Array(params[:entry_ids])).destroy_all.size
    redirect_to intake_registration_path(@registration), notice: "Deleted #{count} #{"sign-up".pluralize(count)}.", status: :see_other
  end

  # GET /registrations/:id/waiting: kiosk sign-ups whose person hasn't
  # opened their invitation yet, with what managers need to chase them.
  def waiting
    @entries = @registration.entries.source_kiosk.unverified.where.not(person_id: nil)
      .includes(:person, :household_members).order(:created_at)
  end

  private

  def require_intake_feature
    redirect_to root_path, notice: "Registration isn't turned on." unless Intake.enabled?
  end

  def set_team
    @team = Team.find(params[:team_id]) if params[:team_id]
  end

  def set_registration
    @registration = authorize policy_scope(Intake::Registration).find(params[:id])
  end

  # Team lists are limited to teams the person manages (any, for admins),
  # badges to those they may give, and the successor to registrations they
  # can see. Teams and badges already on the lists that the person can't
  # choose are kept: someone else put them there.
  def registration_params
    permitted = params.require(:intake_registration).permit(:team_id, :title, :slug, :description, :opens_at, :closes_at,
      :self_service, :kiosk, :gate_approval, :pick_one_required, :guardian_relationship_type_id, :successor_id,
      badge_ids: [], kiosk_field_ids: [], apply_team_ids: [], also_add_team_ids: [], pick_one_team_ids: [], guardian_also_add_team_ids: [])
    manageable = helpers.intake_manageable_teams.pluck(:id)
    %i[apply_team_ids also_add_team_ids pick_one_team_ids guardian_also_add_team_ids].each do |key|
      next unless permitted.key?(key)
      kept = Array(@registration&.public_send(key)) - manageable
      permitted[key] = (Array(permitted[key]).compact_blank & manageable) | kept
    end
    if permitted.key?(:badge_ids)
      assignable = helpers.intake_assignable_badges.map(&:id)
      kept = Array(@registration&.badge_ids) - assignable
      permitted[:badge_ids] = (Array(permitted[:badge_ids]).compact_blank & assignable) | kept
    end
    if permitted[:successor_id].present? && !policy_scope(Intake::Registration).exists?(id: permitted[:successor_id])
      permitted[:successor_id] = @registration&.successor_id
    end
    permitted[:slug] = permitted[:slug].to_s.strip.downcase if permitted.key?(:slug)
    permitted
  end
end
