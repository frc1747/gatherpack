class CommitmentSourcesController < InternalController
  include CommitmentsFeature

  before_action :set_commitment
  before_action :set_source, only: %i[ edit update destroy ]

  # GET /commitments/1/commitment_sources/new?kind=checkins
  def new
    @source = @commitment.commitment_sources.build(kind: params[:kind].presence_in(Commitments.source_kinds.keys) || Commitments.source_kinds.keys.first)
    authorize @source, :create?
    set_subject_choices
  end

  # GET /commitments/1/commitment_sources/1/edit
  def edit
    set_subject_choices
  end

  # POST /commitments/1/commitment_sources
  def create
    @source = @commitment.commitment_sources.build(source_params)
    @source.subject = find_subject(@source.kind_class, params.dig(:commitment_source, :subject_id))
    authorize @source

    if @source.save
      redirect_to edit_path, notice: "Source was added.", status: :see_other
    else
      set_subject_choices
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /commitments/1/commitment_sources/1
  def update
    @source.assign_attributes(source_params.except(:kind))
    @source.subject = find_subject(@source.kind_class, params.dig(:commitment_source, :subject_id)) if params.dig(:commitment_source, :subject_id)
    authorize @source

    if @source.save
      redirect_to edit_path, notice: "Source was updated.", status: :see_other
    else
      set_subject_choices
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /commitments/1/commitment_sources/1
  def destroy
    @source.destroy!
    redirect_to edit_path, notice: "Source was removed.", status: :see_other
  end

  private
    def set_commitment
      @commitment = Commitment.find(params[:commitment_id])
    end

    def set_source
      @source = authorize @commitment.commitment_sources.find(params[:id])
    end

    def set_subject_choices
      kind = @source.kind_class
      @subject_choices = kind ? kind.subject_choices(@commitment, current_user.person).to_a : []
    end

    # Looks the subject up among the kind's own subject class only.
    def find_subject(kind, id)
      return nil if kind.nil? || id.blank?

      kind.subject_type.constantize.find_by(id: id)
    end

    def source_params
      params.require(:commitment_source).permit(:kind, :per, :credits, :max_credits, :position)
    end

    def edit_path
      edit_commitment_path(@commitment, anchor: "sources")
    end
end
