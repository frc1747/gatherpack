class CommitmentsController < InternalController
  include CommitmentsFeature

  FILTERS = %w[ met not_met nothing_planned ].freeze

  before_action :set_commitment, only: %i[ show edit update destroy message ]
  before_action :set_choices, only: %i[ new create edit update ]

  # GET /commitments
  # The viewer's own commitments, then those they run.
  def index
    authorize Commitment
    @person = current_user.person
    commitments = policy_scope(Commitment).includes(:team, :owing_team).order(:starts_on, :title).to_a
    @owed = commitments.select { |commitment| commitment.covers?(@person) }
    @run = commitments.select { |commitment| commitment.organizer?(@person) }
  end

  # GET /commitments/1
  # Organizers get one row per person, filtered by params[:filter]; people
  # who owe see their own progress.
  def show
    @viewer = current_user.person
    if policy(@commitment).progress?
      @filter = params[:filter].presence_in(FILTERS)
      @rows = @commitment.progress(@commitment.owing_people.order(:last_name, :first_name)).values
      @rows = @rows.select { |row| row_matches?(row) } if @filter
    else
      @own = @commitment.progress_for(@viewer)
    end
  end

  # GET /commitments/new
  def new
    authorize Commitment
    team_id = params[:team_id].presence_in(@team_choices.map(&:id)) || @team_choices.first&.id
    @commitment = Commitment.new(team_id: team_id, owing_team_id: team_id, starts_on: Date.current, ends_on: Date.current.end_of_year)
  end

  # GET /commitments/1/edit
  def edit
  end

  # POST /commitments
  def create
    @commitment = authorize Commitment.new(commitment_params.merge(created_by: current_user.person))

    if @commitment.save
      redirect_to edit_commitment_path(@commitment, anchor: "sources"), notice: "Commitment was created. Add the sources that count toward it below."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /commitments/1
  def update
    @commitment.assign_attributes(commitment_params)
    if @commitment.team_id_changed? && !policy(@commitment).team_in_reach?(@commitment.team_id)
      @commitment.errors.add(:team_id, "isn't one you can run commitments for")
      render :edit, status: :unprocessable_entity
    elsif @commitment.save
      redirect_to @commitment, notice: "Commitment was successfully updated.", status: :see_other
    else
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
  # one sees anyone else's address.
  def message
    subject = params[:subject].to_s.strip
    body = params[:body].to_s.strip
    if subject.blank? || body.blank?
      return redirect_to @commitment, alert: "Write a subject and a message.", status: :see_other
    end

    open = @commitment.progress.values.reject(&:met?).map(&:person)
    emails = User.where(id: open.map(&:user_id).compact).pluck(:email).compact_blank.uniq
    emails.each { |email| SendEmailJob.perform_later(Gateway[:email_sending], email, subject, body) }
    redirect_to @commitment, notice: "Message sent to #{helpers.pluralize(emails.size, "person")} with open commitments.", status: :see_other
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
    end

    def row_matches?(row)
      case @filter
      when "met" then row.met?
      when "not_met" then !row.met?
      when "nothing_planned" then row.nothing_planned?
      end
    end

    def commitment_params
      params.require(:commitment).permit(:team_id, :title, :description, :owing_team_id, :owing_badge_id, :base_amount, :unit,
        :counts_when, :starts_on, :ends_on)
    end
end
