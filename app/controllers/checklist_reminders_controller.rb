# Send Reminder on a checklist: who to remind, guardians or not, a note,
# then Preview (the exact email for one person, and their guardians') and
# Send. Behind feature_checklist_reminders.
class ChecklistRemindersController < InternalController
  include ChecklistsFeature

  before_action :require_checklist_reminders
  before_action :load_checklist

  # GET /checklists/1/reminders/new
  def new
    @choices = { who: "everyone", guardians: false, note: "", person_ids: [] }
    @people = Checklists::ReminderBuilder.new(@checklist).people.to_a
  end

  # POST /checklists/1/reminders: sends, or with preview shows the email.
  def create
    @choices = choices
    @people = Checklists::ReminderBuilder.new(@checklist).people.to_a
    sender = Checklists::ReminderSender.new([ reminder_request ], by: current_user.person, note: @choices[:note])

    if params[:preview].present?
      @preview_person = @people.find { |found| found.id == params[:preview_person_id] } || @people.first
      @preview = @preview_person ? sender.messages_about(@preview_person) : []
      return render :new, status: :unprocessable_entity
    end

    if sender.messages.empty?
      return redirect_to new_checklist_checklist_reminder_path(@checklist), alert: "Nobody to remind: everyone chosen is complete, or has no email address.", status: :see_other
    end

    sender.send!
    redirect_to @checklist, notice: sent_notice(sender), status: :see_other
  end

  private

  def require_checklist_reminders
    redirect_to root_path, notice: "Checklist reminders are turned off" unless ChecklistReminder.enabled?
  end

  def load_checklist
    @checklist = policy_scope(Checklist).find(params[:checklist_id])
    authorize @checklist, :create?, policy_class: ChecklistReminderPolicy
  end

  def choices
    permitted = params.fetch(:reminder, {}).permit(:who, :guardians, :note, person_ids: [])
    { who: permitted[:who] == "ticked" ? "ticked" : "everyone", guardians: permitted[:guardians] == "1",
      note: permitted[:note].to_s, person_ids: Array(permitted[:person_ids]).compact_blank }
  end

  def reminder_request
    ids = @choices[:who] == "ticked" ? @choices[:person_ids] : nil
    Checklists::ReminderSender::Request.new(checklist: @checklist, guardians: @choices[:guardians], person_ids: ids)
  end

  def sent_notice(sender)
    people = sender.recipient_count
    guardians = sender.guardian_count
    text = "Reminder sent to #{people} #{"person".pluralize(people)}"
    text += " (#{guardians} of them #{guardians == 1 ? "a guardian" : "guardians"})" if guardians.positive?
    "#{text}."
  end
end
