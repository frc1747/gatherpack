class PersonFieldGroupsController < InternalController
  before_action :set_person_field_group, only: %i[ show edit update destroy move ]

  # GET /person_field_groups
  def index
    authorize PersonFieldGroup
    @person_field_groups = policy_scope(PersonFieldGroup).ordered.includes(:person_fields)
  end

  # GET /person_field_groups/1
  def show
    redirect_to edit_person_field_group_path(@person_field_group)
  end

  # GET /person_field_groups/new
  def new
    @person_field_group = authorize PersonFieldGroup.new(position: (PersonFieldGroup.maximum(:position) || -1) + 1)
  end

  # GET /person_field_groups/1/edit
  def edit
  end

  # POST /person_field_groups
  def create
    @person_field_group = authorize PersonFieldGroup.new(person_field_group_params)

    if @person_field_group.save
      redirect_to person_field_groups_path, notice: "Section was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /person_field_groups/1
  def update
    if @person_field_group.update(person_field_group_params)
      redirect_to person_field_groups_path, notice: "Section was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /person_field_groups/1
  def destroy
    @person_field_group.destroy!
    redirect_to person_field_groups_path, notice: "Section was deleted. Its fields are now ungrouped.", status: :see_other
  end

  # PATCH /person_field_groups/1/move
  def move
    @person_field_group.move(params[:direction])
    redirect_to person_field_groups_path, status: :see_other
  end

  private
    def set_person_field_group
      @person_field_group = authorize policy_scope(PersonFieldGroup).find(params[:id])
    end

    def person_field_group_params
      params.require(:person_field_group).permit(:name, :position)
    end
end
