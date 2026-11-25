# "Move selected to another team" from a team's people (an alumni team,
# say): pick people, optionally narrowed to those with no activity since a
# date, pick the team, see the preview, confirm. Admins and managers of
# both teams.
class TeamMovesController < InternalController
  include HousekeepingFeature

  before_action :set_team

  # GET /teams/:team_id/move_people
  def new
    authorize @team, :manage_members?
    @no_activity = Checklists::RelativeDate.from_config(params.fetch(:no_activity, {}).permit(:mode, :date, :amount, :unit).to_h)
    people = Person.where(id: @team.memberships.where(manager: false).select(:person_id))
    people = Housekeeping.people_without_activity_since(@no_activity.resolve(Date.current), scope: people) if @no_activity
    @people = people.order(:last_name, :first_name)
    @targets = targets
  end

  # POST /teams/:team_id/move_people/preview
  def preview
    authorize @team, :manage_members?
    build_move or return
  end

  # POST /teams/:team_id/move_people
  def create
    authorize @team, :manage_members?
    build_move or return

    moved = @move.apply!
    redirect_to team_memberships_path(@team), notice: "Moved #{moved.size} to #{@move.to.name}.", status: :see_other
  end

  private

  def set_team
    @team = policy_scope(Team).find(params[:team_id])
  end

  # Teams the person may move people to.
  def targets
    teams = current_user.admin? ? Team.all : Team.where(id: current_user.person.all_managed_teams.map(&:id))
    teams.where.not(id: @team.id).order(:name)
  end

  def build_move
    to = targets.find_by(id: params[:to_team_id].to_s.presence)
    ids = Array(params[:ids]).map(&:to_s).grep(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    if to.nil? || ids.empty? || !Housekeeping::MovePeople.allowed?(current_user, @team, to)
      redirect_to team_move_people_path(@team), alert: "Pick the people and a team you manage to move them to.", status: :see_other
      return false
    end

    @move = Housekeeping::MovePeople.new(from: @team, to: to, people: Person.where(id: ids).to_a)
  end
end
