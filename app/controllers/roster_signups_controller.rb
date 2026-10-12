# Organizers add, change, move, cancel and mark sign-ups from the roster.
# Organizers can't mark, move or place against a rule for themselves or a
# relative (SignupPolicy).
class RosterSignupsController < InternalController
  DETAILS = %w[ quantity answer note ].freeze

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
  # Tells the people on the sign-up, once.
  def destroy
    if @signup.cancelled?
      return redirect_to roster_signup_sheet_path(@signup_sheet), alert: "#{@signup.person.display_name}'s sign-up was already cancelled.", status: :see_other
    end

    @signup.cancel!
    SignupNotices.new.cancelled(@signup, by: current_user.person) if @signup.saved_change_to_status?
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
  # Moves the sign-up to another slot on the sheet (signup_slot_id) and
  # tells the people on it.
  def move
    slot = sheet_slots.find(params.dig(:signup, :signup_slot_id))
    @override_rules = params.dig(:signup, :override_rules) == "1"
    authorize @signup, :override? if @override_rules

    from = @signup.signup_slot
    @signup.change!(by: current_user.person, slot: slot, override_rules: @override_rules)
    SignupNotices.new.moved(@signup, from: from, by: current_user.person) if from != slot
    redirect_to roster_signup_sheet_path(@signup_sheet), notice: "#{@signup.person.display_name} moved to #{slot.identifier_name}.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    @signup.restore_attributes
    render :edit, status: :unprocessable_entity
  end

  # PATCH /signup_sheets/1/roster_signups/mark_all_brought?event_id=...
  # Marks every active item sign-up at the event brought, except the
  # organizer's own and their relatives' (another organizer marks those).
  # The organizer then marks what didn't come.
  def mark_all_brought
    authorize @signup_sheet, :roster?
    return redirect_to roster_signup_sheet_path(@signup_sheet), alert: "This sheet is archived.", status: :see_other if @signup_sheet.archived?

    event = @signup_sheet.events.find(params[:event_id])
    signups = Signup.active.joins(signup_slot: :signup_position).includes(:person, :on_behalf_of, signup_slot: :signup_position)
      .where(signup_slots: { event_id: event.id }, signup_positions: { signup_sheet_id: @signup_sheet.id, kind: :items })
    marked, skipped = signups.partition { |signup| policy(signup).mark? }
    Signup.transaction { marked.each { |signup| signup.update!(status: :fulfilled) } }

    notice = "#{helpers.pluralize(marked.size, "sign-up")} at #{event.name} marked brought."
    notice += " #{helpers.pluralize(skipped.size, "sign-up")} left: #{SignupSheet::SELF_APPROVAL_REASON.downcase_first}." if skipped.any?
    redirect_to roster_signup_sheet_path(@signup_sheet, event_id: event.id), notice: notice, status: :see_other
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
