module Orders
  # The approval steps (ApprovalStep, a managed list): like the shared list
  # screen (ManagedListsController), plus each step's minimum and approver
  # rows. Every step has a key that approvals are stored under, so steps are
  # retired rather than deleted.
  class ApprovalStepsController < BaseController
    before_action :set_step, only: %i[edit update move retire restore]

    # GET /orders/approval_steps
    def index
      steps = policy_scope(ApprovalStep, policy_scope_class: ManagedListPolicy::Scope)
        .includes(approvers: %i[badge team])
      authorize ApprovalStep, policy_class: ManagedListPolicy
      @steps = steps.active.ordered
      @retired_steps = steps.retired.ordered
    end

    # GET /orders/approval_steps/new
    def new
      @step = authorize ApprovalStep.new, policy_class: ManagedListPolicy
      @step.approvers.build
    end

    # POST /orders/approval_steps
    def create
      @step = authorize ApprovalStep.new(step_params), policy_class: ManagedListPolicy

      if @step.save
        redirect_to orders_approval_steps_path, notice: "Approval step \"#{@step.name}\" was added."
      else
        @step.approvers.build
        render :new, status: :unprocessable_entity
      end
    end

    # GET /orders/approval_steps/1/edit
    def edit
      @step.approvers.build
    end

    # PATCH/PUT /orders/approval_steps/1
    def update
      if @step.update(step_params)
        redirect_to orders_approval_steps_path, notice: "Approval step \"#{@step.name}\" was saved.", status: :see_other
      else
        @step.approvers.build
        render :edit, status: :unprocessable_entity
      end
    end

    # PATCH /orders/approval_steps/1/move?direction=up|down
    def move
      @step.move!(params[:direction])
      redirect_to orders_approval_steps_path, status: :see_other
    end

    # PATCH /orders/approval_steps/1/retire
    def retire
      @step.retire!
      redirect_to orders_approval_steps_path, notice: "Approval step \"#{@step.name}\" was retired.", status: :see_other
    end

    # PATCH /orders/approval_steps/1/restore
    def restore
      @step.restore!
      redirect_to orders_approval_steps_path, notice: "Approval step \"#{@step.name}\" was restored.", status: :see_other
    end

    private

    def set_step
      @step = authorize ApprovalStep.find(params[:id]), :"#{action_name}?", policy_class: ManagedListPolicy
    end

    def step_params
      params.require(:approval_step).permit(:name, :minimum, approvers_attributes: %i[id badge_id team_id _destroy])
    end
  end
end
