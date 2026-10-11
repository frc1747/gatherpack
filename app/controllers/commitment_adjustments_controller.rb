class CommitmentAdjustmentsController < InternalController
  include CommitmentsFeature

  before_action :set_commitment

  # GET /commitments/1/commitment_adjustments/new?person_id=…
  def new
    @adjustment = @commitment.commitment_adjustments.build(person: owing_person(params[:person_id]))
    authorize @adjustment, :create?
    set_people
  end

  # POST /commitments/1/commitment_adjustments
  def create
    @adjustment = @commitment.commitment_adjustments.build(adjustment_params.merge(created_by: current_user.person))
    @adjustment.person = owing_person(params.dig(:commitment_adjustment, :person_id))
    authorize @adjustment

    if @adjustment.save
      redirect_to @commitment, notice: "Adjustment was recorded.", status: :see_other
    else
      set_people
      render :new, status: :unprocessable_entity
    end
  end

  # DELETE /commitments/1/commitment_adjustments/1
  def destroy
    @adjustment = authorize @commitment.commitment_adjustments.find(params[:id])
    @adjustment.destroy!
    redirect_to @commitment, notice: "Adjustment was removed.", status: :see_other
  end

  private
    def set_commitment
      @commitment = Commitment.find(params[:commitment_id])
    end

    # Only people the commitment covers can be picked, so an organizer
    # can't reach anyone else's record through this form.
    def owing_person(id)
      @commitment.owing_people.find_by(id: id) if id.present?
    end

    # Everyone who owes, less the organizer and their relatives.
    def set_people
      viewer = current_user.person
      @people = @commitment.owing_people.order(:last_name, :first_name).reject { |person| @commitment.self_or_relative?(viewer, person) }
    end

    def adjustment_params
      params.require(:commitment_adjustment).permit(:credits, :reason)
    end
end
