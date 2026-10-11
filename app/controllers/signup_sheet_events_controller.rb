class SignupSheetEventsController < InternalController
  before_action :set_signup_sheet

  # GET /signup_sheets/1/signup_sheet_events/new
  def new
    authorize @signup_sheet.signup_sheet_events.build
    @events = attachable_events
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
