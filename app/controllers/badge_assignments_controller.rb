class BadgeAssignmentsController < InternalController
  before_action :set_badge
  before_action :set_badge_assignment, only: %i[ show edit update destroy ]

  # GET /badge_assignments
  def index
    authorize @badge, policy_class: BadgeAssignmentPolicy
    @q = policy_scope(@badge.badge_assignments).ransack(params[:q])
    @badge_assignments = @q.result(distinct: true).includes(:person).order("people.last_name ASC, people.first_name ASC").page(params[:page])
  end

  # GET /badge_assignments/1
  def show
  end

  # GET /badge_assignments/new
  def new
    @badge_assignment = authorize @badge.badge_assignments.build
  end

  # GET /badge_assignments/1/edit
  def edit
    redirect_to [ @badge, @badge_assignment ]
  end

  # POST /badge_assignments
  def create
    @badge_assignment = authorize @badge.badge_assignments.build(badge_assignment_params)

    if @badge_assignment.save
      redirect_to [ @badge, @badge_assignment ], notice: "Badge assignment was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /badge_assignments/1
  def update
    # The new holder must be someone the user may give this badge to as well.
    @badge_assignment.assign_attributes(badge_assignment_params)
    authorize @badge_assignment

    if @badge_assignment.save
      redirect_to [ @badge, @badge_assignment ], notice: "Badge assignment was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /badge_assignments/1
  def destroy
    @badge_assignment.destroy!
    redirect_to badge_badge_assignments_url(@badge), notice: "Badge assignment was successfully destroyed.", status: :see_other
  end

  private

    def set_badge
      @badge = policy_scope(Badge).find(params[:badge_id])
    end
    # Use callbacks to share common setup or constraints between actions.
    def set_badge_assignment
      @badge_assignment = authorize policy_scope(@badge.badge_assignments).find(params[:id])
    end

    # Only allow a list of trusted parameters through. The badge always comes
    # from the URL, so an assignment can't be moved to another badge.
    def badge_assignment_params
      params.require(:badge_assignment).permit(:person_id)
    end
end
