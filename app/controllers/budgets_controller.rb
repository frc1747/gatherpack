class BudgetsController < InternalController
  before_action :set_budget, only: %i[ show edit update destroy ]

  # GET /budgets
  def index
    @q = policy_scope(Budget).ransack(params[:q])
    @budgets = @q.result(distinct: true).page(params[:page])
  end

  # GET /budgets/1
  def show
    # The budget only counts its own team's entries, which everyone who may
    # see it may open; list them through the scope anyway.
    @ledger_entries = @budget.ledger_entries.where(id: policy_scope(LedgerEntry))
  end

  # GET /budgets/new
  def new
    @budget = authorize Budget.new
  end

  # GET /budgets/1/edit
  def edit
  end

  # POST /budgets
  def create
    @budget = authorize Budget.new(budget_params)

    if @budget.save
      redirect_to @budget, notice: "Budget was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /budgets/1
  def update
    # set_budget checked it as stored; check it in its new period too, so it
    # can't be moved somewhere the user doesn't manage. Only the period is
    # assigned first: assigning ledger_tag_ids saves the taggings at once.
    @budget.assign_attributes(budget_params.slice(:budget_period_id))
    authorize @budget

    if @budget.update(budget_params)
      redirect_to @budget, notice: "Budget was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /budgets/1
  def destroy
    @budget.destroy!
    redirect_to budgets_url, notice: "Budget was successfully destroyed.", status: :see_other
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_budget
      @budget = authorize policy_scope(Budget).find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def budget_params
      params.require(:budget).permit(:amount, :budget_period_id, ledger_tag_ids: [])
    end
end
