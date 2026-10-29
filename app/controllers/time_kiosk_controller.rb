class TimeKioskController < InternalController
  layout "kiosk"

  PUNCH_TOOLS = %w[ punch_in punch_out punch_out_period punch_out_all ].freeze

  rescue_from Pundit::NotAuthorizedError, with: :refuse_kiosk

  def kiosk_page?
    true
  end

  def index
    # The kiosk acts for the person whose card is scanned, not the signed-in
    # user, so it has no scope of its own; who may run it is up to
    # TimeKioskPolicy.
    skip_policy_scope
    authorize :time_kiosk, :use?
    @time_kiosk = TimeKiosk.new(time_kiosk_params)
    # The tool names the partial rendered below, so only these come from the
    # request. Punching changes data, so it takes a POST or PATCH.
    tool = @time_kiosk.tool
    unless tool == "find_token" || (PUNCH_TOOLS.include?(tool) && (request.post? || request.patch?))
      @time_kiosk.tool = "welcome"
    end

    if @time_kiosk.tool == "find_token"
      if @time_kiosk.token
        if @time_kiosk.token.tokenable.is_a?(Person)
          @person = @time_kiosk.person = @time_kiosk.token.tokenable
          @person_ref = @time_kiosk.person_reference
          @time_clocks = @person.time_clock_punches.order(time_clock_period_id: :asc).map do |punch|
            Hash[TimeClockPeriod.find_by_id(punch.time_clock_period_id), punch.hours]
          end.reduce do |a, b|
            a.merge(b) { |_, c, d| c + d }
          end
          @time_clock_periods = @time_kiosk.offered_periods
          @open_punches = @time_kiosk.open_punches
          @time_kiosk.tool = "found_person"
        elsif @time_kiosk.token.tokenable.is_a?(Hook)
          # There is no page for a hook's card yet.
          @hook = @time_kiosk.token.tokenable
          @time_kiosk.tool = "not_found"
        else
          @time_kiosk.tool = "not_found"
        end
      else
        @time_kiosk.tool = "welcome"
      end
    end

    # Punching acts only for the person named by the reference from their
    # scan, and only on the punches and periods that scan offered them.
    if PUNCH_TOOLS.include?(@time_kiosk.tool) && @time_kiosk.person.nil?
      flash.now[:alert] = "Please scan your card again."
      @time_kiosk.tool = "welcome"
    end

    if @time_kiosk.tool == "punch_in"
      if @time_kiosk.time_clock_period && @time_kiosk.offered_periods.include?(@time_kiosk.time_clock_period)
        period = @time_kiosk.time_clock_period
        TimeClockPunch.create(person: @time_kiosk.person, start_time: Time.current, time_clock_period: period, created_by: "kiosk")
      end
      @time_kiosk.tool = "welcome"
    end

    if @time_kiosk.tool == "punch_out"
      if @time_kiosk.time_clock_punch
        punch = @time_kiosk.time_clock_punch
        current_time = Time.current
        max_time = punch.time_clock_period&.end_time&.end_of_day || current_time
        end_time = current_time > max_time ? max_time: current_time

        punch.update(end_time: end_time, created_by: "kiosk")
      end
      @time_kiosk.tool = "welcome"
    end

    if @time_kiosk.tool == "punch_out_period"
      if @time_kiosk.time_clock_period && @time_kiosk.person.user && Pundit.policy(@time_kiosk.person.user, @time_kiosk.time_clock_period).edit?
        period = @time_kiosk.time_clock_period
        current_time = Time.current
        max_time = period&.end_time&.end_of_day || current_time
        end_time = current_time > max_time ? max_time: current_time

        period.open_punches.each do |punch|
          punch.update(end_time: end_time, created_by: "kiosk")
        end
      end
      @time_kiosk.tool = "welcome"
    end

    if @time_kiosk.tool == "punch_out_all"
      current_time = Time.current
      @time_kiosk.managed_periods.each do |period|
        max_time = period&.end_time&.end_of_day || current_time
        end_time = current_time > max_time ? max_time: current_time
        period.open_punches.each do |punch|
          punch.update(end_time: end_time, created_by: "kiosk")
        end
      end
      @time_kiosk.tool = "welcome"
    end

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("kiosk-content", partial: "time_kiosk/kiosk") }
      format.html { render :index }
    end
  end

  private

  def time_kiosk_params
    params.require(:time_kiosk).permit(:tool, :token_value, :time_clock_period_id, :time_clock_punch_id, :person_ref) if params[:time_kiosk]
  end

  # An account that may not run the kiosk is told so rather than sent back
  # to a page that would bring it here again.
  def refuse_kiosk
    render :refused, status: :forbidden, formats: :html
  end
end
