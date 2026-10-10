class TimeKioskController < ApplicationController
  layout "kiosk"
  before_action :require_kiosk_user
  TOOLS = %w[ find_token punch_in punch_out punch_out_period punch_out_all ].freeze
  PUNCH_TOOLS = TOOLS - %w[ find_token ]
  TEST_STORE = ActiveSupport::Cache::MemoryStore.new
  rate_limit to: 60, within: 1.minute, by: -> { current_user.id }, with: -> { show_welcome("Too many scans. Wait a minute and try again.") },
    store: Rails.env.test? ? TEST_STORE : Rails.cache, if: -> { params.dig(:time_kiosk, :tool) == "find_token" }
  before_action -> { show_welcome }, if: -> { PUNCH_TOOLS.include?(params.dig(:time_kiosk, :tool)) && !request.post? }

  def index
    @time_kiosk = TimeKiosk.new(time_kiosk_params)
    @time_kiosk.tool = "welcome" unless TOOLS.include?(@time_kiosk.tool)

    if @time_kiosk.tool == "find_token"
      if @time_kiosk.token
        if @time_kiosk.person
          @person = @time_kiosk.person
          if request.post? && (auto_clock_in = TimeKiosk::AutoClockIn.call(@person))
            flash.now[auto_clock_in.flash_type] = auto_clock_in.message
          end
          @time_clocks = @person.time_clock_punches.order(time_clock_period_id: :asc).map do |punch|
            Hash[TimeClockPeriod.find_by_id(punch.time_clock_period_id), punch.hours]
          end.reduce do |a, b|
            a.merge(b) { |_, c, d| c + d }
          end
          @time_clock_periods = TimeKiosk::AutoClockIn.periods_for(@person)
          @open_punches = TimeClockPunch.all.where(person: @person, end_time: nil)
          @time_clock_periods -= @open_punches.map(&:time_clock_period).compact.uniq
          @time_kiosk.tool = "found_person"
        else
          @time_kiosk.tool = "not_found"
        end
      else
        @time_kiosk.tool = "welcome"
      end
    end

    if PUNCH_TOOLS.include?(@time_kiosk.tool) && @time_kiosk.signed_person.nil?
      flash.now[:warning] = "Please scan your card again."
      @time_kiosk.tool = "welcome"
    end

    if @time_kiosk.tool == "punch_in"
      person = @time_kiosk.signed_person
      period = TimeKiosk::AutoClockIn.periods_for(person).find_by(id: @time_kiosk.time_clock_period_id)
      if @time_kiosk.time_clock_period_id.blank? && !TimeKiosk::Config.allow_unassigned?
        flash.now[:warning] = "Choose a time period."
      elsif period && !TimeClockPunch.exists?(person: person, time_clock_period: period, end_time: nil)
        TimeClockPunch.create(person: person, start_time: Time.current, time_clock_period: period, created_by: "kiosk")
      end
      @time_kiosk.tool = "welcome"
    end

    if @time_kiosk.tool == "punch_out"
      punch = @time_kiosk.signed_person.time_clock_punches.find_by(id: @time_kiosk.time_clock_punch_id, end_time: nil)
      if punch
        current_time = Time.current
        max_time = punch.time_clock_period&.end_time&.end_of_day || current_time
        end_time = current_time > max_time ? max_time: current_time

        punch.update(end_time: end_time, created_by: "kiosk")
      end
      @time_kiosk.tool = "welcome"
    end

    if @time_kiosk.tool == "punch_out_period"
      user = @time_kiosk.signed_person.user
      if @time_kiosk.time_clock_period && user && Pundit.policy(user, @time_kiosk.time_clock_period).edit?
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
      periods = @time_kiosk.signed_person.user ? @time_kiosk.signed_person_managed_periods : []
      periods.each do |period|
        max_time = period&.end_time&.end_of_day || current_time
        end_time = current_time > max_time ? max_time: current_time
        period.open_punches.each do |punch|
          punch.update(end_time: end_time, created_by: "kiosk")
        end
      end
      @time_kiosk.tool = "welcome"
    end

    render_kiosk
  end

  private

  def render_kiosk
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("kiosk-content", partial: "time_kiosk/kiosk") }
      format.html { render :index }
    end
  end

  def show_welcome(message = nil)
    @time_kiosk = TimeKiosk.new(tool: "welcome")
    flash.now[:warning] = message if message
    render_kiosk
  end

  def time_kiosk_params
    params.require(:time_kiosk).permit(:tool, :token_value, :time_clock_period_id, :time_clock_punch_id, :person_ref) if params[:time_kiosk]
  end

  def require_kiosk_user
    team = TimeKiosk::Config.users_team
    return if team.nil? || current_user.admin || current_user.person&.teams&.exists?(id: team.id)

    redirect_to root_path, alert: "The time kiosk is for kiosk accounts only."
  end
end
