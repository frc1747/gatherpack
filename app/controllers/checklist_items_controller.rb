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
    return render(:new, status: :unprocessable_entity) unless authorable?(@item)

    if @item.valid? && needs_confirmation?
      @impact = Checklists::Impact.new(@checklist, items: draft_tree, viewer: current_user.person)
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
    return render(:edit, status: :unprocessable_entity) unless authorable?(@item)

    if @item.valid? && needs_confirmation?
      @impact = Checklists::Impact.new(@checklist, items: draft_tree, viewer: current_user.person)
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
    if needs_confirmation? && (impact = Checklists::Impact.new(@checklist, items: tree_without(@item), viewer: current_user.person)).any?
      return render_impact(impact, url: checklist_checklist_item_path(@checklist, @item), method: :delete)
    end

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
    return render(plain: "You can't set up this item this way.", status: :unprocessable_entity) unless authorable?(item)

    render partial: "checklists/preview", locals: { preview: Checklists::Preview.new(@checklist, item: item, viewer: current_user.person), checklist: @checklist }
  end

  private

  # The kind may refuse a config for this author (ItemKind.authorable_by?).
  def authorable?(item)
    kind = item.kind_class
    return true if kind.nil? || kind.authorable_by?(item, current_user.person)

    item.errors.add(:base, "You can't set up this item this way")
    false
  end

  def set_item
    @item = authorize @checklist.checklist_items.find(params[:id])
  end

  # The checklist's items without this one (and what's inside it).
  def tree_without(item)
    tree = item_tree
    parent = item.parent_id && find_in_tree(tree, item.parent_id)
    if parent
      parent.association(:children).target = parent.children.to_a.reject { |child| child.id == item.id }
    else
      tree.reject! { |top| top.id == item.id }
    end
    tree
  end

  # The checklist's items with the unsaved change in place.
  def draft_tree
    tree = item_tree
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

    permitted = config.permit(*kind.permitted_config).to_h
    hide_unseen_checklists(kind, permitted)
  end

  # A checklist setting may only name a checklist the acting person can see,
  # or its results would show through this one.
  def hide_unseen_checklists(kind, config)
    kind.settings.select { |setting| setting.type == :checklist }.each do |setting|
      id = config[setting.key.to_s]
      config[setting.key.to_s] = nil if id.present? && !policy_scope(Checklist).exists?(id: id)
    end
    config
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
