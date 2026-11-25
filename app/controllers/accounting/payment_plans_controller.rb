# A person's payment plan for a balance rule: their own milestones, which
# replace the rule's for them (AccountingPersonMilestone). Admins only;
# reached from the person's Account tab. Saving or removing the plan works
# out the person's result again.
class Accounting::PaymentPlansController < Accounting::BaseController
  BLANK_ROWS = 2

  before_action :set_plan

  # GET /accounting/rules/:rule_id/payment_plans/:person_id/edit
  def edit
    @rows = @plan + blank_rows(@plan.empty? ? 4 : BLANK_ROWS)
  end

  # PATCH /accounting/rules/:rule_id/payment_plans/:person_id
  def update
    @rows = assign_rows
    kept = @rows.reject { |row| row.marked_for_destruction? || blank?(row) }
    # Every row is checked, so all their errors show at once.
    if kept.map(&:valid?).all? && save_rows(kept)
      evaluate
      redirect_to person_accounting_path(@person), notice: plan_notice(kept), status: :see_other
    else
      # Rows ticked Remove stay on the form, still ticked, so the next Save
      # removes them.
      @rows += blank_rows(BLANK_ROWS)
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /accounting/rules/:rule_id/payment_plans/:person_id
  def destroy
    AccountingPersonMilestone.transaction { @plan.each(&:destroy!) }
    evaluate
    redirect_to person_accounting_path(@person), notice: "Payment plan was removed. #{@person.identifier_name} follows the rule's milestones again.",
      status: :see_other
  end

  private
    def set_plan
      @rule = AccountingRule.find(params[:rule_id])
      authorize @rule, :payment_plan?
      @person = Person.find(params[:person_id])
      raise ActiveRecord::RecordNotFound unless @rule.balance?

      @plan = @rule.person_milestones.where(person: @person).to_a
    end

    def blank_rows(count)
      Array.new(count) { @rule.person_milestones.build(person: @person) }
    end

    # The form's rows onto the plan: existing rows by id (or marked to go),
    # new rows for the rest.
    def assign_rows
      existing = @plan.index_by { |row| row.id.to_s }
      rows = plan_params.map do |attributes|
        row = existing.delete(attributes[:id].to_s) || @rule.person_milestones.build(person: @person, created_by: current_user.person)
        row.assign_attributes(attributes.except(:id, :_destroy))
        row.mark_for_destruction if ActiveModel::Type::Boolean.new.cast(attributes[:_destroy])
        row
      end
      # Rows the form didn't send are left as they were.
      existing.values + rows
    end

    def save_rows(kept)
      AccountingPersonMilestone.transaction do
        @rows.select { |row| row.persisted? && (row.marked_for_destruction? || blank?(row)) }.each(&:destroy!)
        # Only new and changed rows are saved, so update hooks fire only for
        # rows that changed.
        kept.each_with_index do |row, index|
          row.position = index
          row.save! if row.new_record? || row.changed?
        end
      end
      true
    end

    # A new row left empty is a spare row, not a mistake.
    def blank?(row)
      row.new_record? && row.name.blank? && row.due_on.nil? && row.balance_at_most_cents.nil? && row.balance_at_most_percent.nil? && row.note.blank?
    end

    def evaluate
      Accounting::EvaluateRuleJob.perform_later(@rule, [ @person.id ]) if @rule.enabled?
    end

    def plan_notice(kept)
      if kept.any?
        "Payment plan was saved. #{@person.identifier_name}'s result is being worked out again."
      else
        "Payment plan was removed. #{@person.identifier_name} follows the rule's milestones again."
      end
    end

    def plan_params
      rows = params.fetch(:plan, {}).permit(rows: %i[ id name due_on balance_at_most balance_at_most_percent note _destroy ]).fetch(:rows, {})
      rows.to_h.sort_by { |index, _| index.to_i }.map { |_, attributes| attributes.symbolize_keys }
    end
end
