class MembershipsController < InternalController
  include SearchAndAdd

  before_action :set_team_or_person
  before_action :set_membership, only: %i[show edit update destroy]

  # GET /memberships
  def index
    @q = false
    if @team
      @q = policy_scope(Membership).where(team: @team).ransack(params[:q])
      @memberships = @q.result(distinct: true).includes(:person, :team).order("person.last_name" => "desc", "team.name" => "asc").page(params[:page])

      @people_q = @team.all_people.includes(:memberships).ransack(params[:people_q])
      @people = @people_q.result(distinct: true)
      @people = case params[:member_type]
      when "direct"
        @people.where(id: @team.memberships.select(:person_id))
      when "parent_manager"
        @people.where(id: @team.ancestor_manager_ids)
      when "child_member"
        @people.where(id: @team.descendant_member_ids).where.not(id: @team.memberships.select(:person_id))
      else
        @people
      end
      @people = @people.order(last_name: :asc, first_name: :asc).page(params[:people_page])
      load_implied_memberships
      @can_add = policy(@team).manage_members?
      load_team_candidates if @can_add
    elsif @person
      @q = policy_scope(Membership).where(person: @person).ransack(params[:q])
      @memberships = @q.result(distinct: true).includes(:person, :team).order("person.last_name" => "desc", "team.name" => "asc").page(params[:page])
      @can_add = policy(Membership.new(person: @person)).new?
      load_person_candidates if @can_add
    end
    if @team
      render "by_team"
    elsif @person
      render "by_person"
    end
  end

  # GET /teams/1/memberships/candidates or /people/1/memberships/candidates
  def candidates
    if @team
      authorize @team, :manage_members?
      load_team_candidates
    else
      authorize Membership.new(person: @person), :new?
      load_person_candidates
    end
  end

  def show
  end

  def new
    @membership = authorize (@team || @person).memberships.build
  end

  # POST /memberships
  def create
    @membership = authorize (@team || @person).memberships.build(membership_params)

    saved = @membership.save
    if inline_request?
      render :create, status: saved ? :ok : :unprocessable_entity
    elsif saved
      target = if @team
        team_memberships_path(@team)
      else
        person_memberships_path(@person)
      end
      redirect_to target, notice: "Membership was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # PATCH/PUT /memberships/1
  def update
    target = if @team
      team_memberships_path(@team)
    else
      person_memberships_path(@person)
    end
    if @membership.update(membership_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(@membership.person, render_to_string(partial: "memberships/card", locals: { membership: @membership }))
        end
        format.html { redirect_to target, notice: "Membership was successfully updated.", status: :see_other }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /memberships/1
  def destroy
    target = if @team
      team_memberships_path(@team)
    else
      person_memberships_path(@person)
    end
    @membership.destroy!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@membership) }
      format.html { redirect_to target, notice: "Membership was successfully destroyed.", status: :see_other }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_team_or_person
    @team = policy_scope(Team).find(params[:team_id]) if params[:team_id]
    @person = policy_scope(Person).find(params[:person_id]) if params[:person_id]
  end

  def set_membership
    @membership = authorize (@team || @person).memberships.find(params[:id])
  end

  # Why each person on the page who isn't a direct member still shows up: they
  # belong to a team below this one, or manage a team above it.
  def load_implied_memberships
    related = Membership.includes(:team).where(person_id: @people.map(&:id))
    @via_child_teams = related.where(team_id: @team.all_descendant_ids).group_by(&:person_id)
    @via_parent_teams = related.where(team_id: @team.all_ancestor_ids, manager: true).group_by(&:person_id)
  end

  # People the current user could add to @team who aren't direct members yet.
  def load_team_candidates
    people = current_user.admin? ? policy_scope(Person) : current_user.person.all_managed_people
    people = people.where.not(id: @team.memberships.select(:person_id)).order(:last_name, :first_name)
    load_candidates(people, :first_name_or_last_name_or_display_name_cont)
  end

  # Teams the current user could add @person to that they aren't directly in yet.
  def load_person_candidates
    teams = current_user.person.all_managed_teams.where.not(id: @person.memberships.select(:team_id)).order(:name)
    load_candidates(teams, :name_cont)
  end

  # Only allow a list of trusted parameters through.
  def membership_params
    params.require(:membership).permit(:person_id, :team_id, :manager)
  end
end
