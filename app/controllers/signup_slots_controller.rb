class SignupSlotsController < InternalController
  include SignupsFeature

  before_action :set_signup_sheet

  # GET /signup_sheets/1/signup_slots
  # The grid: a row per date, a column per position.
  def index
    authorize @signup_sheet, :manage?
    # One sheet's slots, covered by the sheet check above; nothing to scope.
    skip_policy_scope
    @events = @signup_sheet.events.order(:start_time)
    @positions = @signup_sheet.signup_positions.to_a
    @slots = sheet_slots.index_by { |slot| [ slot.event_id, slot.signup_position_id ] }
  end

  # PATCH /signup_sheets/1/signup_slots/1
  def update
    slot = authorize sheet_slots.find(params[:id])

    if slot.update(slot_params(params.require(:signup_slot)))
      redirect_to signup_sheet_signup_slots_path(@signup_sheet), notice: "#{slot.identifier_name} saved.", status: :see_other
    else
      redirect_to signup_sheet_signup_slots_path(@signup_sheet), alert: "#{slot.identifier_name}: #{slot.errors.full_messages.to_sentence}", status: :see_other
    end
  end

  # PATCH /signup_sheets/1/signup_slots/update_all
  # Saves the whole grid: slots[id][capacity] and slots[id][on].
  def update_all
    authorize @signup_sheet, :manage?
    slots = sheet_slots.index_by(&:id)
    problems = []

    SignupSlot.transaction do
      params.fetch(:slots, {}).each_pair do |id, values|
        slot = slots[id] or next
        slot.assign_attributes(slot_params(values))
        problems << "#{slot.identifier_name}: #{slot.errors.full_messages.to_sentence}" if slot.changed? && !slot.save
      end
      raise ActiveRecord::Rollback if problems.any?
    end

    if problems.any?
      redirect_to signup_sheet_signup_slots_path(@signup_sheet), alert: "Nothing was saved. #{problems.to_sentence}.", status: :see_other
    else
      redirect_to signup_sheet_signup_slots_path(@signup_sheet), notice: "Slots saved.", status: :see_other
    end
  end

  private
    def set_signup_sheet
      @signup_sheet = SignupSheet.find(params[:signup_sheet_id])
    end

    def sheet_slots
      SignupSlot.where(signup_position_id: @signup_sheet.signup_positions.select(:id)).includes(:signup_position, :event)
    end

    # A blank cap means the position's; the slot is off unless "on" is ticked.
    def slot_params(values)
      values = values.permit(:capacity, :on)
      attributes = { capacity: values[:capacity].presence }
      attributes[:disabled] = values[:on] != "1" if values.key?(:on)
      attributes
    end
end
