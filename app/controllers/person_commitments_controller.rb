class PersonCommitmentsController < InternalController
  include CommitmentsFeature

  # GET /people/1/commitments
  # The person's commitments: all of them for the person (with the groups
  # they're related to), and for anyone else only the ones the viewer runs
  # or whose group the viewer is related to.
  def show
    @person = Person.find(params[:person_id])
    policy = PersonCommitmentsPolicy.new(current_user, @person)
    authorize @person, :show?, policy_class: PersonCommitmentsPolicy
    @progress = policy.visible_commitments.map { |commitment| commitment.progress_seen_by(@person) }
  end
end
