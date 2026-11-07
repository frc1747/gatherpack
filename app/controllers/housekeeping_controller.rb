# The bulk bar for one registered type (Housekeeping.register): the list
# narrowed to what ended before a date, then Archive, Restore or Copy
# selected, each previewed before it's done. Records come from the type's
# policy scope, and each is checked again on its own.
class HousekeepingController < InternalController
  include HousekeepingFeature

  ACTIONS = %w[archive restore copy].freeze

  before_action :set_type

  # GET /housekeeping/:type
  # Without filter params it opens on the person's saved default
  # (HousekeepingPreference, "current" when none).
  def index
    @preference = HousekeepingPreference.for(current_user.person, @type.key)
    if filtered?
      @archived = params[:archived].present?
      @older_than = Checklists::RelativeDate.from_config(older_params)
    else
      @archived = @preference.archived?
      @older_than = @preference.older_than
    end
    scope = policy_scope(@type.model)
    scope = @archived ? @type.archived(scope) : @type.unarchived(scope)
    @before = @older_than&.resolve(Date.current)
    scope = @type.ended_by(scope, @before) if @before
    @records = scope.page(params[:page]).per(100)
  end

  # POST /housekeeping/:type/default: the filter shown becomes the
  # person's default for this list.
  def save_default
    authorize :housekeeping, :change?
    older = Checklists::RelativeDate.from_config(older_params)
    HousekeepingPreference.save_for!(current_user.person, @type.key, view: params[:archived].present? ? "archived" : "current", older: older&.to_config)
    redirect_to housekeeping_list_path(@type.key), notice: "Saved as your default for #{@type.label.downcase}.", status: :see_other
  end

  # POST /housekeeping/:type/preview
  def preview
    authorize :housekeeping, :change?
    return redirect_back(fallback_location: housekeeping_list_path(@type.key), alert: "Select at least one first.") if selected.empty?

    build_change
  end

  # POST /housekeeping/:type
  def apply
    authorize :housekeeping, :change?
    build_change
    return redirect_to(housekeeping_list_path(@type.key), alert: "Select at least one first.", status: :see_other) if selected.empty?

    notice = if @copy
      result = @copy.apply!(replace: allowed_replacements)
      text = "#{result[:copies].size} copied as drafts. Check each, then make it active."
      text += " Not copied: #{result[:failed].map { |record, reason| "#{@copy.name_of(record)} (#{reason})" }.to_sentence}." if result[:failed].any?
      left_out = @copy.left_out.sum { |_, rules| rules.size }
      if left_out.positive?
        text += " #{left_out} #{"rule".pluralize(left_out)} naming something deleted #{left_out == 1 ? "was" : "were"} left out " \
          "(#{@copy.left_out.map { |record, _| @copy.name_of(record) }.to_sentence})."
      end
      text
    else
      done = @preview.apply!
      "#{done.size} #{@action == :archive ? "archived" : "restored"}."
    end
    # Back to the view acted on (its filter), not the saved default.
    redirect_to housekeeping_list_path(@type.key, archived: params[:archived].presence, older: older_params.presence || { mode: "" }),
      notice: notice, status: :see_other
  end

  private

  def set_type
    @type = Housekeeping.type(params[:type])
    raise ActiveRecord::RecordNotFound, "No housekeeping for #{params[:type]}" if @type.nil?
  end

  def filtered?
    params.key?(:older) || params.key?(:archived)
  end

  def older_params
    params.fetch(:older, {}).permit(:mode, :date, :amount, :unit).to_h
  end

  def selected
    @selected ||= begin
      ids = Array(params[:ids]).map(&:to_s).grep(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      ids.empty? ? [] : policy_scope(@type.model).where(id: ids).to_a
    end
  end

  def build_change
    @older_than = Checklists::RelativeDate.from_config(older_params)
    @action = ACTIONS.include?(params[:act]) ? params[:act].to_sym : :archive
    if @action == :copy && @type.copyable?
      @shift_months = (params[:shift_months].presence || 12).to_i
      @copy = Housekeeping::BulkCopy.new(@type, selected, current_user, shift_months: @shift_months)
    else
      @action = :archive if @action == :copy
      @preview = Housekeeping::Preview.new(@type, @action, selected, current_user)
    end
  end

  # Picks from the "Old → New" table. A checklist picked must be one the
  # person can see.
  def allowed_replacements
    keys = @copy.replacements.map(&:key)
    replace = params.fetch(:replace, {}).permit(*keys).to_h
    replace.reject { |key, id| key.start_with?("Checklist:") && id.present? && !policy_scope(Checklist).exists?(id: id) }
  end
end
