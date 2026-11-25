class RelationshipsController < InternalController
  before_action :set_person

  def new
    @relationship = authorize Relationship.new(node_occupant: @person)
  end

  def create
    @relationship = Relationship.new(relationship_params)
    @relationship.created_by = current_user.person
    @relationship.node_occupant = @person
    @relationship.reify
    # The other side comes from the form by id, so like the person in the
    # URL it must be someone the user can see, or someone they are already
    # related to (an adult giving a former guardian access again).
    [ @relationship.parent_id, @relationship.child_id ].compact.each do |id|
      policy_scope(Person).find_by(id: id) || related_people.find(id)
    end
    authorize @relationship
    if @relationship.parent.present? && @relationship.child.present?
      if @relationship.save
        redirect_to @person
      else
        render :new, status: 422
      end
    else
      render :new, status: 428
    end
  end

  def reverse
    @relationship = authorize Relationship.find(params[:id])
    @relationship.reverse
    @relationship.created_by = current_user.person
    if @relationship.save
      redirect_to relationships_person_path(@person), notice: "Relationship was successfully reversed."
    else
      redirect_to relationships_person_path(@person), notice: "Relationship was not successfully reversed."
    end
  end

  def destroy
    @relationship = authorize Relationship.find(params[:id])
    @relationship.destroy
    redirect_to relationships_person_path(@person), notice: "Relationship was successfully destroyed."
  end

  private
  # People on either side of a relationship with the signed-in person.
  def related_people
    me = current_user.person
    Person.where(id: Relationship.where(child_id: me.id).select(:parent_id))
      .or(Person.where(id: Relationship.where(parent_id: me.id).select(:child_id)))
  end

  def set_person
    @person = policy_scope(Person).find(params[:person_id])
  end

  def relationship_params
    params.require(:relationship).permit(:parent_id, :child_id, :relationship_type_id, :start_node)
  end
end
