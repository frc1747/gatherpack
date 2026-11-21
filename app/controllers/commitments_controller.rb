class CommitmentsController < InternalController
  include CommitmentsFeature

  STATUSES = { "met" => "Met", "not_met" => "Not met", "nothing_planned" => "Nothing planned" }.freeze
  EDIT_TABS = %w[ details sources organizers ].freeze

  before_action :set_commitment, only: %i[ show edit update destroy message ]
  before_action :set_choices, only: %i[ new create edit update ]

  # GET /commitments
  # The viewer's own commitments (their group's progress, or that of the
  # group they're related to), then those they run.
  def index
    authorize Commitment
    @person = current_user.person
    commitments = policy_scope(Commitment).includes(:team, :owing_team).order(:starts_on, :title).to_a
    @run = commitments.select { |commitment| commitment.organizer?(@person) }
    @owed = commitments.filter_map do |commitment|
      commitment.progress_seen_by(@person) if @run.exclude?(commitment) || commitment.covers?(@person)
    end
  end

  # GET /commitments/1
  # Organizers get one row per person or group, filtered by params[:team_id]
  # and params[:status]; people who owe (and those related to a group) see
  # their own progress.
  def show
    @viewer = current_user.person
    if policy(@commitment).progress?
      set_progress_rows
    else
      @own = @commitment.progress_seen_by(@viewer)
    end
  end

  # GET /commitments/new
  def new
    authorize Commitment
    team_id = params[:team_id].presence_in(@team_choices.map(&:id)) || @team_choices.first&.id
    @commitment = Commitment.new(team_id: team_id, owing_team_id: team_id, starts_on: Date.current, ends_on: Date.current.end_of_year)
  end

  # GET /commitments/1/edit?tab=sources
  # One tab per part: details (the form), sources (what counts), organizers.
  def edit
    @tab = params[:tab].presence_in(EDIT_TABS) || "details"
  end

  # POST /commitments
  def create
    @commitment = authorize Commitment.new(commitment_params.merge(created_by: current_user.person))

    if @commitment.save
      redirect_to edit_commitment_path(@commitment, tab: "sources"), notice: "Commitment was created. Add the sources that count toward it below."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /commitments/1
  def update
    @commitment.assign_attributes(commitment_params)
    if @commitment.team_id_changed? && !policy(@commitment).team_in_reach?(@commitment.team_id)
      @commitment.errors.add(:team_id, "isn't one you can run commitments for")
      @tab = "details"
      render :edit, status: :unprocessable_entity
    elsif @commitment.save
      redirect_to @commitment, notice: "Commitment was successfully updated.", status: :see_other
    else
      @tab = "details"
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /commitments/1
  def destroy
    @commitment.destroy!
    redirect_to commitments_url, notice: "Commitment was successfully destroyed.", status: :see_other
  end

  # POST /commitments/1/message
  # Emails everyone who hasn't met the commitment, one message each so no
  # one sees anyone else's address (Commitments::Message). Without a subject
  # or message, the page comes back with the message card open.
  def message
    subject = params[:subject].to_s.strip
    body = params[:body].to_s.strip
    if subject.blank? || body.blank?
      @viewer = current_user.person
      @message = { subject: subject, body: body, error: "Write a subject and a message." }
      set_progress_rows
      return render :show, status: :unprocessable_entity
    end

    sent = Commitments::Message.new(@commitment, from: current_user.person).deliver(subject: subject, body: body)
    redirect_to @commitment, notice: "Message sent to #{helpers.pluralize(sent, "person")} with open commitments.", status: :see_other
  end

  private
    def set_commitment
      @commitment = Commitment.find(params[:id])
      authorize @commitment, { "show" => :show?, "message" => :message? }.fetch(action_name, :manage?)
    end

    def set_choices
      ids = Commitment.creatable_team_ids(current_user.person)
      ids |= [ @commitment.team_id ] if @commitment&.persisted?
      @team_choices = Team.where(id: ids).order(:name).to_a
      @badge_choices = GatherPack::Features.enabled?(:badges) ? Badge.order(:name).to_a : []
      # Only trusted types, plus the saved one so a type that isn't (any
      # more) shows with its error.
      types = Commitment.trusted_relationship_types
      types = types.or(RelationshipType.where(id: @commitment.group_relationship_type_id)) if @commitment&.group_relationship_type_id
      @relationship_type_choices = types.order(:parent_label).to_a
    end

    # Everyone's rows (@rows, filtered by team and status), the status pills'
    # counts within the team, and how many people haven't met it (Remind).
    def set_progress_rows
      rows = @commitment.progress(@commitment.owing_people.order(:last_name, :first_name)).values.uniq
      @open_count = rows.reject(&:met?).sum { |row| row.members.size }
      @teams = [ @commitment.owing_team, *@commitment.owing_team.all_descendants ]
      @team = @teams.find { |team| team.id.to_s == params[:team_id].to_s }
      if @team
        ids = @team.descendant_people.pluck(:id).to_set
        rows = rows.select { |row| row.members.any? { |member| ids.include?(member.id) } }
      end
      @status_counts = STATUSES.keys.index_with { |status| rows.count { |row| row_matches?(row, status) } }
      @status = params[:status].presence_in(STATUSES.keys)
      @rows = @status ? rows.select { |row| row_matches?(row, @status) } : rows
    end

    def row_matches?(row, status)
      case status
      when "met" then row.met?
      when "not_met" then !row.met?
      when "nothing_planned" then row.nothing_planned?
      end
    end

    def commitment_params
      params.require(:commitment).permit(:team_id, :title, :description, :owing_team_id, :owing_badge_id, :exempt_badge_id, :base_amount,
        :group_relationship_type_id, :additional_amount, :unit, :counts_when, :starts_on, :ends_on)
    end
end
