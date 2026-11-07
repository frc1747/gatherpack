# Excusing a person from one meeting on an attendance item (spec §7),
# included in ChecklistExcusesController by
# config/initializers/checklists_attendance.rb. The "Excuse" link on an
# attendance item opens a page to pick the meeting, which links on to
# excusing the whole item (whole=1). A create with an event_id excuses just
# that meeting: it leaves the person's required and credited hours.
module ChecklistMeetingExcuses
  extend ActiveSupport::Concern

  included do
    before_action :offer_meeting_excuse, only: :new
    before_action :create_meeting_excuse, only: :create
  end

  private

  # GET /checklists/1/excuses/new?item_id=..&person_id=..
  def offer_meeting_excuse
    item = find_item(params[:item_id])
    return unless attendance?(item) && params[:whole].blank?

    @excuse = authorize ChecklistExcuse.new(item: item, person: find_person(params[:person_id]))
    load_meetings
    render "checklist_excuses/meeting"
  end

  # POST /checklists/1/excuses with checklist_excuse[event_id]
  def create_meeting_excuse
    attributes = params.require(:checklist_excuse).permit(:item_id, :person_id, :event_id, :reason, :expires_on)
    return if attributes[:event_id].blank?

    item = find_item(attributes[:item_id])
    @excuse = ChecklistExcuse.new(reason: attributes[:reason], expires_on: attributes[:expires_on], item: item,
      person: find_person(attributes[:person_id]), created_by: current_user.person)
    authorize @excuse
    load_meetings
    @excuse.event = @meetings.find { |meeting| meeting.id == attributes[:event_id] } if attendance?(item)

    if @excuse.event.nil?
      @excuse.errors.add(:base, "Pick one of this item's meetings")
      render "checklist_excuses/meeting", status: :unprocessable_entity
    elsif @excuse.save
      redirect_to checklist_path(@checklist), status: :see_other,
        notice: "#{@excuse.person.display_name} excused from #{@excuse.event.name.presence || "the meeting"}."
    else
      render "checklist_excuses/meeting", status: :unprocessable_entity
    end
  end

  def attendance?(item)
    item.kind_class == Checklists::Kinds::Attendance
  end

  # The item's held meetings, newest first, with the time the person was
  # there, and the meetings they're already excused from.
  def load_meetings
    @meetings = []
    @time_at_meetings = {}
    @meeting_excuses = ChecklistExcuse.none
    return unless attendance?(@excuse.item)

    kind = Checklists::Kinds::Attendance.new(@excuse.item, Checklists::Context.new(@checklist))
    @meeting_excuses = ChecklistExcuse.where(item: @excuse.item, person: @excuse.person).where.not(event_id: nil)
      .includes(:event, :created_by).order(:created_at)
    excused = @meeting_excuses.map(&:event_id)
    @meetings = kind.meetings.reverse.reject { |meeting| excused.include?(meeting.id) }
    @time_at_meetings = kind.time_at_meetings(@excuse.person.id)
  end
end
