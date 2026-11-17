module Orders
  class FundingSourcesController < BaseController
    before_action :set_funding_source, only: %i[show edit update destroy report]

    # GET /orders/funding_sources
    def index
      @funding_sources = policy_scope(FundingSource).includes(:team).order(active: :desc, name: :asc)
    end

    # GET /orders/funding_sources/1
    def show
    end

    # GET /orders/funding_sources/new
    def new
      @funding_source = authorize FundingSource.new(active: true)
    end

    # GET /orders/funding_sources/1/edit
    def edit
    end

    # POST /orders/funding_sources
    def create
      @funding_source = authorize FundingSource.new(funding_source_params)

      if team_in_reach?(@funding_source) && @funding_source.save
        attach_new_documents
        redirect_to orders_funding_source_path(@funding_source), notice: "Funding source was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /orders/funding_sources/1
    def update
      @funding_source.assign_attributes(funding_source_params)

      if team_in_reach?(@funding_source) && @funding_source.save
        attach_new_documents
        purge_removed_documents
        redirect_to orders_funding_source_path(@funding_source), notice: "Funding source was successfully updated.", status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /orders/funding_sources/1
    def destroy
      if @funding_source.destroy
        redirect_to orders_funding_sources_path, notice: "Funding source was successfully deleted.", status: :see_other
      else
        redirect_to orders_funding_source_path(@funding_source), alert: "#{@funding_source.name} has been used, so it can't be deleted. Untick In use instead.", status: :see_other
      end
    end

    # GET /orders/funding_sources/1/report(.csv)
    def report
      @report = Orders::FundingReport.new(@funding_source)
      respond_to do |format|
        format.html
        format.csv do
          send_data @report.to_csv, type: "text/csv", filename: "#{@funding_source.name.parameterize}-report.csv"
        end
      end
    end

    private

    def set_funding_source
      @funding_source = authorize policy_scope(FundingSource).find(params[:id])
    end

    def funding_source_params
      params.require(:funding_source).permit(:team_id, :name, :kind, :amount, :starts_on, :ends_on, :restriction, :giver, :reference,
        :report_due_on, :spent_outside, :spent_outside_as_of, :active)
    end

    # A funding manager only sets up sources for teams they reach.
    def team_in_reach?(funding_source)
      return true if funding_source.team_id.blank? || Orders::Access.for(current_user.person).funding_manager_for?(funding_source.team_id)

      funding_source.errors.add(:team, "isn't one you manage funding for")
      false
    end

    # Added on top of what's attached: assigning documents= would replace
    # them all, and the file field also sends a blank entry.
    def attach_new_documents
      files = Array(params.dig(:funding_source, :documents)).compact_blank
      @funding_source.documents.attach(files) if files.any?
    end

    def purge_removed_documents
      Array(params[:remove_document_ids]).each do |id|
        @funding_source.documents.find_by(id: id)&.purge_later
      end
    end
  end
end
