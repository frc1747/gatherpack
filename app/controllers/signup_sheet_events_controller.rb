# Add dates: organizers make new events for the sheet's team (authorized by
# the sheet, not EventPolicy, spec §3.6) or attach existing ones. They can
# later change the name, place and time of the events the sheet made.
class SignupSheetEventsController < InternalController
  NEW_ROWS = 5
  MAX_ROWS = 50

  before_action :set_signup_sheet
  before_action :set_signup_sheet_event, only: %i[ edit update ]

  # GET /signup_sheets/1/signup_sheet_events/new
  def new
    authorize @signup_sheet.signup_sheet_events.build
    @rows = Array.new(NEW_ROWS) { SignupDateRow.new }
    @event_type_id = @signup_sheet.event_type_id
    set_attachable_events
  end

  # POST /signup_sheets/1/signup_sheet_events/create_dates
  # Makes an event for each filled-in row of dates[] (date, start_time,
  # end_time, name, location), of dates_event_type_id, for the sheet's team. With
  # "more", shows the form again with more rows, saving nothing.
  def create_dates
    authorize SignupSheetEvent.new(signup_sheet: @signup_sheet), :create?
    @rows = date_rows_params.map { |row| SignupDateRow.new(row.to_h) }
    @event_type_id = params[:dates_event_type_id].presence
    if params[:more].present?
      @rows += Array.new([ NEW_ROWS, MAX_ROWS - @rows.size ].min) { SignupDateRow.new }
      return render_new
    end

    filled = @rows.reject(&:empty?)
    event_type = EventType.find_by(id: @event_type_id)
    @dates_error = if filled.empty? then "Fill in at least one date."
    elsif event_type.nil? then "Pick an event type."
    end
    return render_new(:unprocessable_entity) if @dates_error || !filled.map(&:valid?).all?

    events = filled.map do |row|
      Event.new(team: @signup_sheet.team, event_type: event_type, **row.event_attributes(@signup_sheet.title))
    end
    filled.zip(events).each { |row, event| event.errors.each { |error| row.errors.add(:base, error.full_message) } unless event.valid? }
    return render_new(:unprocessable_entity) if filled.any? { |row| row.errors.any? }

    SignupSheetEvent.transaction do
      @signup_sheet.update!(event_type: event_type) if @signup_sheet.event_type_id != event_type.id
      events.each do |event|
        event.save!
        @signup_sheet.signup_sheet_events.create!(event: event, created_by_sheet: true)
      end
    end
    redirect_to edit_signup_sheet_path(@signup_sheet, anchor: "dates"),
      notice: "#{helpers.pluralize(events.size, "date")} added. Each position now has a slot on each date.", status: :see_other
  end

  # GET /signup_sheets/1/signup_sheet_events/1/edit
  def edit
    @row = SignupDateRow.from_event(@event)
  end

  # PATCH/PUT /signup_sheets/1/signup_sheet_events/1
  # Changes the name, place, date and time of an event the sheet made.
  # Everyone signed up hears about a new date or time (Signups::EventChanges).
  def update
    @row = SignupDateRow.new(params.require(:date).permit(:date, :start_time, :end_time, :name, :location).to_h)
    return render :edit, status: :unprocessable_entity unless @row.valid?

    if @event.update(@row.event_attributes(@event.name))
      redirect_to edit_signup_sheet_path(@signup_sheet, anchor: "dates"), notice: "#{@event.name} saved.", status: :see_other
    else
      @event.errors.each { |error| @row.errors.add(:base, error.full_message) }
      render :edit, status: :unprocessable_entity
    end
  end

  # POST /signup_sheets/1/signup_sheet_events
  # Attaches the ticked events (event_ids[]).
  def create
    authorize @signup_sheet.signup_sheet_events.build
    ids = Array(params[:event_ids]).compact_blank.uniq
    events = attachable_events.where(id: ids).to_a
    return redirect_to new_signup_sheet_signup_sheet_event_path(@signup_sheet), alert: "Tick at least one event.", status: :see_other if ids.empty?
    if events.size < ids.size
      return redirect_to new_signup_sheet_signup_sheet_event_path(@signup_sheet), alert: "Only events listed here can be added. Nothing was added.", status: :see_other
    end

    SignupSheetEvent.transaction do
      events.each { |event| @signup_sheet.signup_sheet_events.create!(event: event) }
    end
    redirect_to edit_signup_sheet_path(@signup_sheet, anchor: "dates"),
      notice: "#{helpers.pluralize(events.size, "date")} added. Each position now has a slot on each date.", status: :see_other
  end

  # DELETE /signup_sheets/1/signup_sheet_events/1
  def destroy
    @signup_sheet_event = authorize @signup_sheet.signup_sheet_events.find(params[:id])

    if @signup_sheet_event.destroy
      redirect_to edit_signup_sheet_path(@signup_sheet, anchor: "dates"), notice: "#{@signup_sheet_event.event.name} removed from the sheet.", status: :see_other
    else
      redirect_to edit_signup_sheet_path(@signup_sheet, anchor: "dates"), alert: @signup_sheet_event.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private
    def set_signup_sheet
      @signup_sheet = SignupSheet.find(params[:signup_sheet_id])
    end

    def set_signup_sheet_event
      @signup_sheet_event = authorize @signup_sheet.signup_sheet_events.find(params[:id])
      @event = @signup_sheet_event.event
    end

    def set_attachable_events
      events = attachable_events
      @event_types = EventType.where(id: events.select(:event_type_id)).order(:name)
      @events = params[:event_type_id].present? ? events.where(event_type_id: params[:event_type_id]) : events
    end

    def render_new(status = :ok)
      set_attachable_events
      render :new, status: status
    end

    # The dates[] rows, given as dates[0][date], dates[1][date], ...
    def date_rows_params
      rows = params.fetch(:dates, {})
      rows = rows.values if rows.respond_to?(:values)
      rows.first(MAX_ROWS).map { |row| row.permit(:date, :start_time, :end_time, :name, :location) }
    end

    # Upcoming events of the sheet's team and the teams below it that the
    # organizer can already see and that aren't on the sheet yet.
    def attachable_events
      team = @signup_sheet.team
      policy_scope(Event).where(team_id: [ team.id ] + team.all_descendant_ids)
        .where(start_time: Time.current.beginning_of_day..)
        .where.not(id: @signup_sheet.signup_sheet_events.select(:event_id))
        .order(:start_time)
    end
end
