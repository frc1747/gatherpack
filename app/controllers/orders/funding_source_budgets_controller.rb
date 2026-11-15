module Orders
  # Links a funding source to a GatherPack Budget (spec §6), for funding
  # managers while Budgets is on. The approve screen then shows the
  # Budget's amount and its spending in the ledger next to the source.
  class FundingSourceBudgetsController < BaseController
    before_action :require_budgets
    before_action :set_funding_source

    # GET /orders/funding_sources/1/budget/edit
    def edit
      @budgets = budget_choices
    end

    # PATCH /orders/funding_sources/1/budget
    def update
      budget_id = params.dig(:funding_source, :budget_id).presence
      # The current Budget stays a choice even when it's outside the
      # person's budgets (an admin linked it).
      budget = budget_id && (budget_id == @funding_source.budget_id ? @funding_source.budget : budget_choices.find { |choice| choice.id == budget_id })
      raise Orders::Refused, "Choose one of the budgets listed." if budget_id && budget.nil?

      @funding_source.link_budget!(budget)
      notice = budget ? "#{@funding_source.name} is linked to #{budget.identifier_name}." : "#{@funding_source.name} has no budget now."
      redirect_to edit_orders_funding_source_budget_path(@funding_source), notice: notice
    end

    private

    def require_budgets
      redirect_to orders_requests_path, notice: "Budgets are turned off" unless Orders::LedgerRecording.budgets_on?
    end

    def set_funding_source
      @funding_source = authorize policy_scope(FundingSource).find(params[:funding_source_id]), :update?
    end

    def budget_choices
      @budget_choices ||= policy_scope(Budget).includes(:ledger_tags, budget_period: :team)
        .sort_by { |budget| [ -budget.budget_period.starts_at.to_i, budget.identifier_name ] }
    end
  end
end
