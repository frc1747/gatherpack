class SignupSheetsController < InternalController
  before_action :set_signup_sheet, only: %i[ show edit update destroy ]
  before_action :set_team_choices, only: %i[ new create edit update ]

  # GET /signup_sheets
  def index
    authorize SignupSheet
    @signup_sheets = policy_scope(SignupSheet).visible.includes(:team).order(:title)
  end

  # GET /signup_sheets/1
  def show
    @events = @signup_sheet.events.order(:start_time)
  end

  # GET /signup_sheets/new
  def new
    authorize SignupSheet
    team_id = params[:team_id].presence_in(@team_choices.map(&:id)) || @team_choices.first&.id
    @signup_sheet = SignupSheet.new(team_id: team_id)
  end

  # GET /signup_sheets/1/edit
  def edit
  end

  # POST /signup_sheets
  def create
    @signup_sheet = authorize SignupSheet.new(signup_sheet_params.merge(created_by: current_user.person))

    if @signup_sheet.save
      redirect_to @signup_sheet, notice: "Sign-up sheet was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /signup_sheets/1
  def update
    @signup_sheet.assign_attributes(signup_sheet_params)
    if @signup_sheet.team_id_changed? && !policy(@signup_sheet).team_in_reach?(@signup_sheet.team_id)
      @signup_sheet.errors.add(:team_id, "isn't one you can run sheets for")
      render :edit, status: :unprocessable_entity
    elsif @signup_sheet.save
      redirect_to @signup_sheet, notice: "Sign-up sheet was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /signup_sheets/1
  # A sheet with sign-ups is archived instead.
  def destroy
    if policy(@signup_sheet).destroy?
      @signup_sheet.destroy!
      redirect_to signup_sheets_url, notice: "Sign-up sheet was successfully destroyed.", status: :see_other
    else
      @signup_sheet.archived!
      redirect_to signup_sheets_url, notice: "Sign-up sheet has sign-ups, so it was archived instead.", status: :see_other
    end
  end

  private
    def set_signup_sheet
      @signup_sheet = SignupSheet.find(params[:id])
      authorize @signup_sheet, action_name == "show" ? :show? : :manage?
    end

    def set_team_choices
      ids = SignupSheet.creatable_team_ids(current_user.person)
      ids |= [ @signup_sheet.team_id ] if @signup_sheet&.persisted?
      @team_choices = Team.where(id: ids).order(:name).to_a
    end

    def signup_sheet_params
      params.require(:signup_sheet).permit(:team_id, :title, :description, :contact, :status, :names_permission,
        :on_behalf_of_mode, :cancel_cutoff_hours, others_relationship_type_ids: [])
    end
end
