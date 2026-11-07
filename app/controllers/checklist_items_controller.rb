class ChecklistItemsController < InternalController
  include ChecklistsFeature

  before_action :set_checklist
  before_action :set_item, only: %i[ edit update destroy ]

  # GET /checklists/1/items/new?kind=badge
  def new
    @item = authorize @checklist.checklist_items.new(kind: params[:kind], parent_id: params[:parent_id])
    @item.label = @item.kind_label if @item.kind_class
  end

  # GET /checklists/1/items/1/edit
  def edit
  end

  # POST /checklists/1/items
  def create
    @item = authorize @checklist.checklist_items.new(kind: params.dig(:checklist_item, :kind))
    @item.assign_attributes(item_params)

    if @item.valid? && needs_confirmation?
      @impact = Checklists::Impact.new(@checklist, items: draft_tree)
      return render(:new, status: :unprocessable_entity) if @impact.any?
    end

    if @item.save
      redirect_to @checklist, notice: "#{@item.label} added.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /checklists/1/items/1
  def update
    @item.assign_attributes(item_params)

    if @item.valid? && needs_confirmation?
      @impact = Checklists::Impact.new(@checklist, items: draft_tree)
      return render(:edit, status: :unprocessable_entity) if @impact.any?
    end

    if @item.save
      redirect_to @checklist, notice: "#{@item.label} saved.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /checklists/1/items/1
  def destroy
    @item.destroy!
    redirect_to @checklist, notice: "#{@item.label} removed.", status: :see_other
  end

  # POST /checklists/1/items/preview: who the draft item passes.
  def preview
    item = params[:id].present? ? @checklist.checklist_items.find(params[:id]) : @checklist.checklist_items.new(kind: params.dig(:checklist_item, :kind))
    authorize item, :preview?
    @item = item
    item.assign_attributes(item_params)
    item.id ||= SecureRandom.uuid
    render partial: "checklists/preview", locals: { preview: Checklists::Preview.new(@checklist, item: item), checklist: @checklist }
  end

  private

  def set_item
    @item = authorize @checklist.checklist_items.find(params[:id])
  end

  def needs_confirmation?
    @checklist.active? && params[:confirmed].blank?
  end

  # The checklist's items with the unsaved change in place.
  def draft_tree
    tree = @checklist.top_level_items.includes(children: :children).to_a
    @item.id ||= SecureRandom.uuid
    if @item.parent_id.present?
      parent = all_items(tree).find { |item| item.id == @item.parent_id }
      parent.children.target.reject! { |child| child.id == @item.id } if parent
      parent&.children&.target&.push(@item)
    else
      index = tree.index { |item| item.id == @item.id }
      index ? tree[index] = @item : tree << @item
    end
    tree
  end

  def all_items(items)
    items.flat_map { |item| [ item ] + all_items(item.children.to_a) }
  end

  # The kind's own fields only.
  def config_params
    kind = @item&.kind_class || Checklists.item_kind(params.dig(:checklist_item, :kind))
    config = params.dig(:checklist_item, :config)
    return {} unless kind && config.respond_to?(:permit)

    keys = kind.settings.map { |setting| %i[badges teams].include?(setting.type) ? { setting.key => [] } : setting.key }
    config.permit(*keys).to_h
  end

  def item_params
    permitted = params.fetch(:checklist_item, {}).permit(:label, :counts, :starts_on, :starts_within_amount, :starts_within_unit,
      :ends_on, :due_on, :read_level, :exempt_label, :parent_id, :position, :start_mode)
    mode = permitted.delete(:start_mode)
    if mode == "within"
      permitted[:starts_on] = nil
    elsif mode == "checklist"
      permitted[:starts_on] = nil
      permitted[:starts_within_amount] = nil
    elsif mode
      permitted[:starts_within_amount] = nil
    end
    permitted[:parent_id] = nil unless @checklist.checklist_items.where(id: permitted[:parent_id]).exists?
    permitted[:config_params] = config_params
    permitted
  end
end
