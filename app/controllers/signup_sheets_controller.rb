class SignupSheetsController < InternalController
  include SignupsFeature

  before_action :set_signup_sheet, only: %i[ show edit update destroy roster archive restore ]
  before_action :set_team_choices, only: %i[ new create edit update ]

  # The setup page's tabs; slots are set on the Dates tab.
  EDIT_TABS = %w[ details positions dates organizers audience ].freeze
  # The "Taking sign-ups" choices. Archiving is its own action.
  TAKING_SIGNUPS = %w[ draft open closed ].freeze

  # GET /signup_sheets
  # Open sheets, plus any the person runs; those with their sign-ups first,
  # then by next date. Filtered by title and team (params[:q]). Archived
  # sheets are left out; people who run sheets can list the archived ones
  # they run instead (params[:archived]), to open and restore them.
  def index
    authorize SignupSheet
    person = current_user.person
    sheets = policy_scope(SignupSheet).includes(:team).to_a
    organized = sheets.select { |sheet| sheet.organizer?(person) }
    @organized_ids = organized.map(&:id)
    @runs_sheets = organized.any? || policy(SignupSheet).new?
    @archived = @runs_sheets && params[:archived] == "1"
    listed = if @archived
      organized.select(&:archived?)
    else
      sheets.select { |sheet| !sheet.archived? && (sheet.open? || @organized_ids.include?(sheet.id)) }
    end
    @team_choices = listed.map(&:team).uniq.sort_by(&:name)
    @q = SignupSheet.where(id: listed.map(&:id)).ransack(params[:q])
    @signup_sheets = @q.result.includes(:team).to_a

    ids = @signup_sheets.map(&:id)
    @my_counts = signups_involving(Signup.live, person).joins(signup_slot: :signup_position)
      .where(signup_positions: { signup_sheet_id: ids }).group("signup_positions.signup_sheet_id").count
    upcoming = SignupSheetEvent.joins(:event).where(signup_sheet_id: ids, events: { start_time: Time.current.. }).group(:signup_sheet_id)
    @next_dates = upcoming.minimum("events.start_time")
    @last_dates = upcoming.maximum("events.start_time")
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
    @age_check = Signups::AgeCheck.new(@signup_sheet, @viewer)
  end

  # GET /signup_sheets/1/roster
  # Every sign-up on the sheet, filtered by event_id, signup_position_id and
  # status.
  def roster
    @events = @signup_sheet.events.order(:start_time)
    @positions = @signup_sheet.signup_positions.to_a
    @signups = Signup.where(signup_slot_id: @signup_sheet.signup_slots.select(:id))
      .joins(signup_slot: %i[ event signup_position ])
      .includes({ person: :user }, :on_behalf_of, :signed_up_by, signup_slot: [ :event, { signup_position: :signup_position_rules } ])
      .order("events.start_time", "signup_positions.position", "signups.created_at")
    @signups = @signups.where(signup_slots: { event_id: params[:event_id] }) if params[:event_id].present?
    @signups = @signups.where(signup_slots: { signup_position_id: params[:signup_position_id] }) if params[:signup_position_id].present?
    @status_counts = @signups.unscope(:order).group(:status).count
    @signups = @signups.where(status: params[:status]) if params[:status].to_s.in?(Signup.statuses.keys)
  end

  # GET /signup_sheets/new
  def new
    authorize SignupSheet
    team_id = params[:team_id].presence_in(@team_choices.map(&:id)) || @team_choices.first&.id
    @signup_sheet = SignupSheet.new(team_id: team_id)
  end

  # GET /signup_sheets/1/edit?tab=dates
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

  # POST /signup_sheets/1/archive
  # Hides the sheet from lists; its sign-ups are kept.
  def archive
    @signup_sheet.archived!
    redirect_to @signup_sheet, notice: "Sheet archived.", status: :see_other
  end

  # POST /signup_sheets/1/restore
  # Brings an archived sheet back closed, until someone chooses to take
  # sign-ups again.
  def restore
    @signup_sheet.closed!
    redirect_to @signup_sheet, notice: "Sheet restored. It isn't taking sign-ups.", status: :see_other
  end

  # DELETE /signup_sheets/1
  # A sheet with sign-ups is archived instead. The sheet page only offers
  # Delete when it can delete; Archive has its own action.
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
      authorize @signup_sheet, { "show" => :show?, "roster" => :roster?, "archive" => :archive?, "restore" => :restore? }.fetch(action_name, :manage?)
      @tab = params[:tab].presence_in(EDIT_TABS) || "details"
    end

    def set_team_choices
      ids = SignupSheet.creatable_team_ids(current_user.person)
      ids |= [ @signup_sheet.team_id ] if @signup_sheet&.persisted?
      @team_choices = Team.where(id: ids).order(:name).to_a
    end

    # Sign-ups the person takes, made, or that are on their behalf. Placing
    # someone from the roster doesn't count as making their sign-up.
    def signups_involving(signups, person)
      return signups.none if person.nil?

      signups.where(person_id: person.id).or(signups.where(on_behalf_of_id: person.id))
        .or(signups.where(signed_up_by_id: person.id, placed_by_organizer: false))
    end

    # Taking sign-ups sets the status, but never to or from archived.
    def signup_sheet_params
      permitted = [ :team_id, :title, :description, :contact, :names_permission, :on_behalf_of_mode, :cancel_cutoff_hours,
        { others_relationship_type_ids: [] } ]
      permitted << :status if !@signup_sheet&.archived? && TAKING_SIGNUPS.include?(params.dig(:signup_sheet, :status))
      params.require(:signup_sheet).permit(*permitted)
    end
end
