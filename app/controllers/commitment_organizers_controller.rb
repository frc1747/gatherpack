class CommitmentOrganizersController < InternalController
  include CommitmentsFeature

  before_action :set_commitment

  # POST /commitments/1/commitment_organizers
  # Only people holding an organizer badge that reaches the commitment's
  # team can be added (CommitmentOrganizer checks).
  def create
    person = Person.find_by(id: params.dig(:commitment_organizer, :person_id))
    @organizer = authorize @commitment.commitment_organizers.build(person: person)

    if @organizer.save
      redirect_to edit_path, notice: "#{person.display_name} can now run this commitment.", status: :see_other
    else
      redirect_to edit_path, alert: "That organizer couldn't be added: #{@organizer.errors.full_messages.to_sentence}.", status: :see_other
    end
  end

  # DELETE /commitments/1/commitment_organizers/1
  def destroy
    @organizer = authorize @commitment.commitment_organizers.find(params[:id])
    if @commitment.commitment_organizers.count <= 1
      return redirect_to edit_path, alert: "A commitment needs at least one organizer. Add another before removing this one.", status: :see_other
    end

    @organizer.destroy!
    notice = "#{@organizer.person.display_name} no longer runs this commitment."
    if @commitment.organizer?(current_user.person)
      redirect_to edit_path, notice: notice, status: :see_other
    else
      redirect_to commitments_path, notice: notice, status: :see_other
    end
  end

  private
    def set_commitment
      @commitment = Commitment.find(params[:commitment_id])
    end

    def edit_path
      edit_commitment_path(@commitment, anchor: "organizers")
    end
end
