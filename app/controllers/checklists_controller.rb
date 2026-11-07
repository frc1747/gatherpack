class ChecklistsController < InternalController
  include ChecklistsFeature

  before_action :load_checklist, only: %i[ show edit update destroy copy_form copy preview refresh restore ]

  # GET /checklists
  def index
    @q = policy_scope(Checklist).ransack(params[:q])
    @q.sorts = "title asc" if @q.sorts.empty?
    @checklists = @q.result.includes(:team)
    @checklists = @checklists.where.not(status: :archived) unless params[:archived].present?
  end

  # GET /checklists/1
  def show
    @organizer = policy(@checklist).update?
    @full_view = Checklists::Visibility.new(@checklist, current_user.person).full?
    @as_of = parse_date(params[:as_of]) if @organizer
    @report = Checklists::Report.new(@checklist, current_user.person, as_of: @as_of)
  end

  # GET /checklists/new
  def new
    @checklist = authorize Checklist.new(status: :draft, starts_on: Date.current)
  end

  # GET /checklists/1/edit
  def edit
  end

  # POST /checklists
  def create
    @checklist = authorize Checklist.new(checklist_params.merge(created_by: current_user.person))

    if @checklist.save
      redirect_to @checklist, notice: "Checklist made. Add its items next."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /checklists/1
  def update
    @checklist.assign_attributes(checklist_params)
    if @checklist.valid? && needs_confirmation?
      @impact = Checklists::Impact.new(@checklist, viewer: current_user.person)
      return render(:edit, status: :unprocessable_entity) if @impact.any?
    end

    if @checklist.save
      redirect_to @checklist, notice: "Checklist saved.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /checklists/1
  def destroy
    if @checklist.destroy
      redirect_to checklists_url, notice: "Checklist deleted.", status: :see_other
    else
      redirect_to @checklist, alert: @checklist.errors.full_messages.to_sentence, status: :see_other
    end
  end

  # GET /checklists/1/copy
  def copy_form
    @shift_months = (params[:shift_months].presence || 12).to_i
    @copier = Checklists::Copier.new(@checklist, shift_months: @shift_months)
  end

  # POST /checklists/1/copy
  def copy
    copier = Checklists::Copier.new(@checklist, shift_months: params[:shift_months].to_i)
    dates = params.fetch(:dates, {}).permit(*copier.date_changes.map(&:key)).to_h
    replace = params.fetch(:replace, {}).permit(*copier.replacements.map(&:key)).to_h
    # A replacement checklist must be one the person can see.
    replace.reject! { |key, id| key.start_with?("Checklist:") && id.present? && !policy_scope(Checklist).exists?(id: id) }
    begin
      copy = copier.call(title: params[:title], by: current_user.person, dates: dates, replace: replace)
    rescue Checklists::Copier::Refused => e
      alerts = []
      alerts << "You can't copy #{e.items.to_sentence}: ask someone who can set those items up." if e.items.any?
      alerts << "You can't copy #{e.grants.to_sentence}: ask someone who can grant it." if e.grants.any?
      return redirect_to(copy_checklist_path(@checklist), alert: alerts.join(" "), status: :see_other)
    end

    left_out = copier.empty_rules.size
    notice = "Copied as a draft. Check it, then make it active."
    notice += " #{left_out} #{"rule".pluralize(left_out)} naming something deleted #{left_out == 1 ? "was" : "were"} left out." if left_out.positive?
    redirect_to copy, notice: notice, status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to copy_checklist_path(@checklist), alert: "Couldn't copy: #{e.record.errors.full_messages.to_sentence}", status: :see_other
  end

  # POST /checklists/1/preview: who the population would cover with a new rule.
  def preview
    rules = @checklist.population_rules.to_a
    draft = @checklist.checklist_rules.new(rule_params)
    rules << draft if draft.valid?
    @preview = Checklists::Preview.new(@checklist, rules: rules, viewer: current_user.person)
    render partial: "checklists/preview", locals: { preview: @preview, checklist: @checklist }
  end

  # POST /checklists/1/refresh: recompute everyone now, silently.
  def refresh
    Checklists::Refresher.new(@checklist, silent: true).call
    redirect_to @checklist, notice: "Results recomputed.", status: :see_other
  end

  # POST /checklists/1/restore: an archived checklist runs again.
  def restore
    @checklist.update!(status: :active)
    redirect_to @checklist, notice: "Checklist restored.", status: :see_other
  end

  private

  def load_checklist
    @checklist = authorize policy_scope(Checklist).find(params[:id])
  end

  def needs_confirmation?
    super &&
      (@checklist.changed & %w[team_id starts_on starts_within_amount starts_within_unit ends_on cutoff_on]).any?
  end

  def parse_date(value)
    Date.iso8601(value) if value.present?
  rescue Date::Error
    nil
  end

  def checklist_params
    permitted = params.require(:checklist).permit(:title, :description, :team_id, :starts_on, :starts_within_amount,
      :starts_within_unit, :ends_on, :cutoff_on, :status, :read_level, :met_word, :pending_word, :not_met_word, :start_mode)
    mode = permitted.delete(:start_mode)
    if mode == "within"
      permitted[:starts_on] = nil
    elsif mode
      permitted[:starts_within_amount] = nil
    end
    if @checklist&.persisted? && permitted[:team_id].present? && !Checklist.creatable_team_ids(current_user.person).include?(permitted[:team_id])
      permitted.delete(:team_id)
    end
    permitted
  end

  def rule_params
    params.fetch(:checklist_rule, {}).permit(:effect, :target_type, :team_id, :badge_id, :person_id, :include_managers)
  end
end
