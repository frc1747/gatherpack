class PersonCommitmentsController < InternalController
  include CommitmentsFeature

  # GET /people/1/commitments
  # The person's commitments: all of them for the person, and only the ones
  # the viewer runs for anyone else.
  def show
    @person = Person.find(params[:person_id])
    policy = PersonCommitmentsPolicy.new(current_user, @person)
    authorize @person, :show?, policy_class: PersonCommitmentsPolicy
    @progress = policy.visible_commitments.map { |commitment| commitment.progress_for(@person) }
  end
end
