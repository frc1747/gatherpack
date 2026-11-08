# Organizers email everyone signed up for one date on their sheet. Each
# person gets their own email, so no one (the organizer included) sees the
# addresses.
class SignupMessagesController < InternalController
  include SignupsFeature

  before_action :set_signup_sheet

  # GET /signup_sheets/1/signup_messages/new?event_id=...
  def new
    @event_id = params[:event_id]
  end

  # POST /signup_sheets/1/signup_messages
  def create
    @event_id, @subject, @body = params.values_at(:event_id, :subject, :body).map { |value| value.to_s.strip }
    event = @signup_sheet.events.find_by(id: @event_id)
    @error = if event.nil? then "Pick a date."
    elsif @subject.blank? || @body.blank? then "Write a subject and a message."
    end
    return render :new, status: :unprocessable_entity if @error

    sent = SignupNotices.new.message(@signup_sheet, event, subject: @subject, body: @body, from: current_user.person)
    if sent.zero?
      redirect_to roster_signup_sheet_path(@signup_sheet, event_id: event.id), alert: "No one signed up for #{event.name} has an email address, so nothing was sent.", status: :see_other
    else
      redirect_to roster_signup_sheet_path(@signup_sheet, event_id: event.id), notice: "Message sent to #{helpers.pluralize(sent, "person")}.", status: :see_other
    end
  end

  private
    def set_signup_sheet
      @signup_sheet = authorize SignupSheet.find(params[:signup_sheet_id]), :roster?
      @events = @signup_sheet.events.order(:start_time)
    end
end
