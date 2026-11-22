# One admin screen for every registered managed list (GatherPack::ManagedLists):
# the list's rows in order, with add, edit, reorder, retire/restore, delete
# (when unused) and merge (when in use).
class ManagedListsController < InternalController
  before_action :set_list
  before_action :set_row, except: %i[index new create]

  # GET /lists/:list
  def index
    rows = policy_scope(@list.model, policy_scope_class: ManagedListPolicy::Scope)
    authorize @list.model, policy_class: ManagedListPolicy
    @retired = params[:status] == "retired"
    @active_count = rows.active.count
    @retired_count = rows.retired.count
    @rows = (@retired ? rows.retired : rows.active).ordered
  end

  # GET /lists/:list/rows/new
  def new
    @row = authorize @list.model.new, policy_class: ManagedListPolicy
  end

  # GET /lists/:list/rows/1/edit
  def edit
  end

  # POST /lists/:list/rows
  def create
    @row = authorize @list.model.new(row_params), policy_class: ManagedListPolicy

    if @row.save
      redirect_to managed_list_path(@list.key), notice: "#{@list.label} \"#{@row.name}\" was added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /lists/:list/rows/1
  def update
    if @row.update(row_params)
      redirect_to managed_list_path(@list.key), notice: "#{@list.label} \"#{@row.name}\" was saved.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /lists/:list/rows/1
  def destroy
    if @row.destroy
      redirect_to managed_list_path(@list.key), notice: "#{@list.label} \"#{@row.name}\" was deleted.", status: :see_other
    else
      flash[:danger] = @row.errors.full_messages.to_sentence
      redirect_to managed_list_path(@list.key), status: :see_other
    end
  end

  # PATCH /lists/:list/rows/1/move?direction=up|down
  def move
    @row.move!(params[:direction])
    redirect_to managed_list_path(@list.key), status: :see_other
  end

  # PATCH /lists/:list/rows/1/retire
  def retire
    @row.retire!
    redirect_to managed_list_path(@list.key), notice: "#{@list.label} \"#{@row.name}\" was retired.", status: :see_other
  end

  # PATCH /lists/:list/rows/1/restore
  def restore
    @row.restore!
    redirect_to managed_list_path(@list.key), notice: "#{@list.label} \"#{@row.name}\" was restored.", status: :see_other
  end

  # GET /lists/:list/rows/1/merge
  def merge
    @targets = merge_targets
  end

  # POST /lists/:list/rows/1/merge
  def merge_into
    target = merge_targets.find_by(id: params[:target_id])
    if target.nil? || @row.key.present?
      @targets = merge_targets
      flash.now[:danger] = target ? "#{@row.name} is built in and can't be merged away." : "Choose the #{@list.label.downcase} to merge into."
      render :merge, status: :unprocessable_entity
    else
      @row.merge_into!(target)
      redirect_to managed_list_path(@list.key), notice: "#{@list.label} \"#{@row.name}\" was merged into \"#{target.name}\".", status: :see_other
    end
  end

  private

  def set_list
    @list = GatherPack::ManagedLists.find(params[:list])
    raise ActiveRecord::RecordNotFound, "No managed list #{params[:list]}" unless @list&.available?
  end

  def set_row
    action = action_name == "merge_into" ? :merge? : :"#{action_name}?"
    @row = authorize @list.model.find(params[:id]), action, policy_class: ManagedListPolicy
  end

  def merge_targets
    @list.model.active.ordered.where.not(id: @row.id)
  end

  def row_params
    params.require(:row).permit(:name, :plural, *@list.fields.map(&:name))
  end
end
