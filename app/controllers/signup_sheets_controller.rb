class SignupSheetsController < InternalController
  include SignupsFeature

  before_action :set_signup_sheet, only: %i[ show edit update destroy roster ]
  before_action :set_team_choices, only: %i[ new create edit update ]

  # GET /signup_sheets
  # Open sheets, plus any the person runs; those with their sign-ups first,
  # then by next date.
  def index
    authorize SignupSheet
    person = current_user.person
    sheets = policy_scope(SignupSheet).visible.includes(:team).to_a
    @organized_ids = sheets.select { |sheet| sheet.organizer?(person) }.map(&:id)
    @signup_sheets = sheets.select { |sheet| sheet.open? || @organized_ids.include?(sheet.id) }

    ids = @signup_sheets.map(&:id)
    @my_counts = signups_involving(Signup.live, person).joins(signup_slot: :signup_position)
      .where(signup_positions: { signup_sheet_id: ids }).group("signup_positions.signup_sheet_id").count
    @next_dates = SignupSheetEvent.joins(:event).where(signup_sheet_id: ids, events: { start_time: Time.current.. })
      .group(:signup_sheet_id).minimum("events.start_time")
    @signup_sheets.sort_by! do |sheet|
      [ @my_counts[sheet.id].to_i.positive? ? 0 : 1, @next_dates[sheet.id]&.to_f || Float::INFINITY, sheet.title.downcase ]
    end
  end

  # GET /signup_sheets/1
  def show
    @viewer = current_user.person
    @events = @signup_sheet.events.order(:start_time).to_a
    @slots_by_event = @signup_sheet.signup_slots.where(disabled: false).includes(signup_position: :signup_position_rules, signups: :person)
      .sort_by { |slot| [ slot.signup_position.position, slot.signup_position.created_at ] }.group_by(&:event_id)
    @my_signups = signups_involving(@signup_sheet.signups.live, @viewer)
      .includes(:person, :signed_up_by, :on_behalf_of, signup_slot: %i[ event signup_position ])
      .sort_by { |signup| [ signup.event.start_time, signup.signup_position.position ] }
    @takers = @signup_sheet.takers_for(@viewer).to_a
    @names_visible = @signup_sheet.names_visible_to?(@viewer)
  end

  # GET /signup_sheets/1/roster
  # Every sign-up on the sheet, filtered by event_id, signup_position_id and
  # status.
  def roster
    @events = @signup_sheet.events.order(:start_time)
    @positions = @signup_sheet.signup_positions.to_a
    @signups = Signup.where(signup_slot_id: @signup_sheet.signup_slots.select(:id))
      .joins(signup_slot: %i[ event signup_position ])
      .includes(:person, :on_behalf_of, signup_slot: [ :event, { signup_position: :signup_position_rules } ])
      .order("events.start_time", "signup_positions.position", "signups.created_at")
    @signups = @signups.where(signup_slots: { event_id: params[:event_id] }) if params[:event_id].present?
    @signups = @signups.where(signup_slots: { signup_position_id: params[:signup_position_id] }) if params[:signup_position_id].present?
    @signups = @signups.where(status: params[:status]) if params[:status].to_s.in?(Signup.statuses.keys)
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
      authorize @signup_sheet, { "show" => :show?, "roster" => :roster? }.fetch(action_name, :manage?)
    end

    def set_team_choices
      ids = SignupSheet.creatable_team_ids(current_user.person)
      ids |= [ @signup_sheet.team_id ] if @signup_sheet&.persisted?
      @team_choices = Team.where(id: ids).order(:name).to_a
    end

    # Sign-ups the person takes, made, or that are on their behalf.
    def signups_involving(signups, person)
      return signups.none if person.nil?

      signups.where(person_id: person.id).or(signups.where(signed_up_by_id: person.id)).or(signups.where(on_behalf_of_id: person.id))
    end

    def signup_sheet_params
      params.require(:signup_sheet).permit(:team_id, :title, :description, :contact, :status, :names_permission,
        :on_behalf_of_mode, :cancel_cutoff_hours, others_relationship_type_ids: [])
    end
end
