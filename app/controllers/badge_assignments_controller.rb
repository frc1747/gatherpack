class BadgeAssignmentsController < InternalController
  include SearchAndAdd

  before_action :set_badge
  before_action :set_badge_assignment, only: %i[ show edit update destroy ]

  # GET /badge_assignments
  def index
    authorize @badge, policy_class: BadgeAssignmentPolicy
    @q = policy_scope(@badge.badge_assignments).ransack(params[:q])
    @badge_assignments = @q.result(distinct: true).includes(:person).order("people.last_name ASC, people.first_name ASC").page(params[:page])
    @can_assign = policy(BadgeAssignment.new(badge: @badge)).create?
    load_badge_candidates if @can_assign
  end

  # GET /badge_assignments/candidates
  def candidates
    authorize BadgeAssignment.new(badge: @badge), :create?
    load_badge_candidates
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

    saved = @badge_assignment.save
    if inline_request?
      render :create, status: saved ? :ok : :unprocessable_entity
    elsif saved
      redirect_to [ @badge, @badge_assignment ], notice: "Badge assignment was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /badge_assignments/1
  def update
    if @badge_assignment.update(badge_assignment_params)
      redirect_to [ @badge, @badge_assignment ], notice: "Badge assignment was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /badge_assignments/1
  def destroy
    @badge_assignment.destroy!
    if inline_request?
      render :destroy
    else
      redirect_to badge_badge_assignments_url(@badge), notice: "Badge assignment was successfully destroyed.", status: :see_other
    end
  end

  private

    def set_badge
      @badge = policy_scope(Badge).find(params[:badge_id])
    end
    # Use callbacks to share common setup or constraints between actions.
    def set_badge_assignment
      @badge_assignment = authorize policy_scope(@badge.badge_assignments).find(params[:id])
    end

    # People who could be given this badge and don't have it yet. Mirrors the
    # search scopes the single-entry form uses.
    def eligible_people
      people = if @badge.team
        policy_scope(@badge.team.all_people)
      elsif current_user.admin?
        policy_scope(Person)
      else
        current_user.person.all_managed_people
      end
      people.where.not(id: @badge.badge_assignments.select(:person_id))
    end

    def load_badge_candidates
      load_candidates(eligible_people.order(:last_name, :first_name), :first_name_or_last_name_or_display_name_cont)
    end

    # Only allow a list of trusted parameters through.
    def badge_assignment_params
      params.require(:badge_assignment).permit(:badge_id, :person_id)
    end
end
