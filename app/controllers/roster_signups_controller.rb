# Organizers add, change, move, cancel and mark sign-ups from the roster.
# Organizers can't mark, move or place against a rule for themselves or a
# relative (SignupPolicy).
class RosterSignupsController < InternalController
  DETAILS = %w[ extra_people extra_names quantity answer note ].freeze

  before_action :set_signup_sheet
  before_action :set_signup, only: %i[ edit update destroy mark move ]

  # GET /signup_sheets/1/roster_signups/new
  def new
    slot = sheet_slots.find_by(id: params[:signup_slot_id]) || sheet_slots.first
    return redirect_to roster_signup_sheet_path(@signup_sheet), alert: "Add positions and dates before placing anyone.", status: :see_other unless slot

    @signup = authorize Signup.new(signup_slot: slot), :place?
  end

  # GET /signup_sheets/1/roster_signups/1/edit
  def edit
  end

  # POST /signup_sheets/1/roster_signups
  # Places anyone the sheet is open to; with override_rules, even if they
  # don't meet the position's rules.
  def create
    values = signup_params
    slot = sheet_slots.find(values[:signup_slot_id])
    person = @signup_sheet.audience.find_by(id: values[:person_id])
    on_behalf_of = @signup_sheet.audience.find_by(id: values[:on_behalf_of_id]) || person
    @override_rules = values[:override_rules] == "1"
    @signup = Signup.new(signup_slot: slot, person: person, on_behalf_of: on_behalf_of, **values.slice(*DETAILS).to_h.symbolize_keys)
    authorize @signup, :place?

    if person.nil?
      @signup.errors.add(:person, "must be someone the sheet is open to")
      return render :new, status: :unprocessable_entity
    end

    # The box only matters when a rule fails; then the no-self rule applies.
    if @override_rules
      if slot.signup_position.eligible?(person, slot.event)
        @override_rules = false
      elsif !policy(@signup).override?
        @signup.errors.add(:base, policy(@signup).self_approval_reason || "You can't place someone against a rule")
        return render :new, status: :unprocessable_entity
      end
    end

    begin
      Signup.place!(slot: slot, person: person, signed_up_by: current_user.person, on_behalf_of: on_behalf_of,
        override_rules: @override_rules, **values.slice(*DETAILS).to_h.symbolize_keys)
      redirect_to roster_signup_sheet_path(@signup_sheet), notice: "#{person.display_name} placed in #{slot.identifier_name}.", status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      @signup.errors.merge!(e.record.errors)
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /signup_sheets/1/roster_signups/1
  def update
    @signup.change!(by: current_user.person, **signup_params.slice(*DETAILS).to_h.symbolize_keys)
    redirect_to roster_signup_sheet_path(@signup_sheet), notice: "Sign-up for #{@signup.person.display_name} saved.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
  end

  # DELETE /signup_sheets/1/roster_signups/1
  def destroy
    @signup.cancel!
    redirect_to roster_signup_sheet_path(@signup_sheet), notice: "Sign-up for #{@signup.person.display_name} cancelled.", status: :see_other
  end

  # PATCH /signup_sheets/1/roster_signups/1/mark?status=fulfilled|no_show|active
  # No-show only once the event has started.
  def mark
    status = params[:status].to_s.presence_in(%w[ fulfilled no_show active ])
    alert = if status.nil? then "Pick fulfilled or no-show."
    elsif @signup.cancelled? then "This sign-up was cancelled."
    elsif status == "no_show" && @signup.event.start_time > Time.current then "Mark no-shows once the event has started."
    end
    return redirect_to roster_signup_sheet_path(@signup_sheet), alert: alert, status: :see_other if alert

    @signup.update!(status: status)
    redirect_to roster_signup_sheet_path(@signup_sheet), notice: "#{@signup.person.display_name}: #{helpers.roster_status_label(@signup)}.", status: :see_other
  end

  # PATCH /signup_sheets/1/roster_signups/1/move
  # Moves the sign-up to another slot on the sheet (signup_slot_id).
  def move
    slot = sheet_slots.find(params.dig(:signup, :signup_slot_id))
    @override_rules = params.dig(:signup, :override_rules) == "1"
    authorize @signup, :override? if @override_rules

    @signup.change!(by: current_user.person, slot: slot, override_rules: @override_rules)
    redirect_to roster_signup_sheet_path(@signup_sheet), notice: "#{@signup.person.display_name} moved to #{slot.identifier_name}.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    @signup.restore_attributes
    render :edit, status: :unprocessable_entity
  end

  private
    def set_signup_sheet
      @signup_sheet = SignupSheet.find(params[:signup_sheet_id])
    end

    def set_signup
      @signup = Signup.where(signup_slot_id: sheet_slots.select(:id)).find(params[:id])
      authorize @signup, { "mark" => :mark?, "move" => :move? }.fetch(action_name, :place?)
    end

    def sheet_slots
      SignupSlot.where(signup_position_id: @signup_sheet.signup_positions.select(:id))
        .joins(:event, :signup_position).order("events.start_time", "signup_positions.position")
    end

    def signup_params
      params.require(:signup).permit(:signup_slot_id, :person_id, :on_behalf_of_id, :override_rules, *DETAILS)
    end
end
