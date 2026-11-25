# The Reminders section of a checklist's Edit page: what reminders may say,
# for the checklist and each item, and its scheduled reminders.
class ChecklistReminderSettingsController < InternalController
  include ChecklistsFeature

  before_action :require_checklist_reminders
  before_action :load_checklist

  # PATCH /checklists/1/reminder_settings
  def update
    items = @checklist.checklist_items.index_by(&:id)
    saved = Checklist.transaction do
      item_levels.each do |id, level|
        item = items[id]
        next unless item && item.email_level.to_s != level.to_s

        item.update!(email_level: level)
      end
      @checklist.update(settings_params) || raise(ActiveRecord::Rollback)
    end

    if saved
      redirect_to edit_checklist_path(@checklist, tab: "reminders"), notice: "Reminder settings saved.", status: :see_other
    else
      redirect_to edit_checklist_path(@checklist, tab: "reminders"), alert: @checklist.errors.full_messages.to_sentence, status: :see_other
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_checklist_path(@checklist, tab: "reminders"), alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  private

  def require_checklist_reminders
    redirect_to root_path, notice: "Checklist reminders are turned off" unless ChecklistReminder.enabled?
  end

  def load_checklist
    @checklist = policy_scope(Checklist).find(params[:checklist_id])
    authorize @checklist, :update?, policy_class: ChecklistReminderPolicy
  end

  def settings_params
    params.require(:checklist).permit(:email_level, :reminders_scheduled, :reminder_every_days, :reminder_days_before_end,
      :reminder_guardians, :reminder_via_digest)
  end

  def item_levels
    params.fetch(:item_levels, {}).permit(*@checklist.checklist_items.ids.map(&:to_s)).to_h.select { |_, level| level.blank? || Checklists::EmailLevel.valid?(level) }
  end
end
