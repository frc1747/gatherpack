class FormsController < InternalController
  # The Preview as… form. The people pickers show the selected person's name
  # by calling #viewer and #subject.
  Preview = Struct.new(:viewer_id, :subject_id) do
    def viewer
      Person.find_by(id: viewer_id) if viewer_id.present?
    end

    def subject
      Person.find_by(id: subject_id) if subject_id.present?
    end
  end

  before_action :require_feature
  before_action :set_form, except: %i[ index new create order_sheet ]

  # GET /forms
  def index
    authorize Form
    @entries = helpers.form_entries_for(current_user.person)
    @managed = policy_scope(Form).visible.includes(:team).order(Arel.sql("status = 1 DESC"), :title)
  end

  # GET /forms/1
  def show
    @teams = helpers.form_team_choices(@form)
    @team = @teams.detect { |team| team.id == params[:team_id] }
    @report = FormReport.new(@form, viewer: current_user.person, team: @team)
    @status = FormReport::STATUSES.include?(params[:status]) ? params[:status] : nil
  end

  # GET /forms/new
  def new
    teams = policy(Form.new).assignable_teams
    # From an event page: a form for that event, owned by the event's team.
    event = policy_scope(Event).find_by(id: params[:event_id]) if params[:event_id]
    event = nil unless event&.team && teams.where(id: event.team_id).exists?
    @form = Form.new(team: event&.team || teams.order(:name).first, event: event)
    authorize @form, :new?
  end

  EDIT_TABS = %w[ details questions audience permissions responses ].freeze

  # GET /forms/1/edit?tab=questions
  def edit
  end

  # POST /forms
  def create
    @form = Form.new(form_params.merge(created_by: current_user.person))
    authorize @form

    if @form.save
      # Starts by asking the owning team, as before audience rules; the
      # builder can change that.
      @form.form_audience_rules.create!(effect: :include, target_type: :team, team: @form.event&.team || @form.team)
      redirect_to edit_form_path(@form, tab: "questions"), notice: "Form was created. Add its questions below."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /forms/1
  def update
    @form.assign_attributes(form_params)
    form_policy = policy(@form)
    # A form run only by its creator stays an event form of one of their teams.
    allowed = form_policy.creator_only? ? form_policy.create? : form_policy.manage?
    if allowed && @form.save
      redirect_to edit_form_path(@form, tab: @tab), notice: "Form was saved.", status: :see_other
    else
      unless allowed
        message = form_policy.creator_only? ? "must be an event of a team you belong to" : "must be one you manage"
        @form.errors.add(form_policy.creator_only? ? :event : :team, message)
      end
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /forms/1
  def destroy
    @form.destroy!
    redirect_to forms_path, notice: "Form was deleted.", status: :see_other
  end

  # POST /forms/1/open
  def open
    return redirect_to edit_form_path(@form, tab: "audience"), alert: "Add someone to ask before opening the form.", status: :see_other unless @form.openable?

    @form.update!(status: :open)
    redirect_to form_path(@form), notice: "Form is open for responses.", status: :see_other
  end

  # POST /forms/1/publish
  def publish
    reconfirm = params[:reconfirm] == "1"
    @form.publish!(reconfirm: reconfirm)
    notice = reconfirm ? "Changes were published. Earlier responses need to be reviewed and signed again." : "Changes were published. Earlier responses stay complete."
    redirect_to edit_form_path(@form), notice: notice, status: :see_other
  end

  # GET /forms/1/audience
  # The people behind "Asks N people".
  def audience
    @people = @form.audience.order(:last_name, :first_name)
    @former = @form.former_subjects.order(:last_name, :first_name)
  end

  # POST /forms/1/close
  def close
    @form.update!(status: :closed)
    redirect_to form_path(@form), notice: "Form is closed.", status: :see_other
  end

  # POST /forms/1/archive
  def archive
    @form.update!(status: :archived)
    redirect_to forms_path, notice: "Form was archived.", status: :see_other
  end

  # POST /forms/1/duplicate
  def duplicate
    copy = @form.duplicate!(title: "#{@form.title} (copy)", created_by: current_user.person)
    redirect_to edit_form_path(copy, tab: "details"), notice: "Form was duplicated. Its responses weren't copied.", status: :see_other
  end

  # POST /forms/1/remind
  def remind
    team = Team.find_by(id: params[:team_id])
    report = FormReport.new(@form, viewer: current_user.person, team: team)
    pending = report.rows.reject { |row| %w[ complete no_longer_asked ].include?(row.status) }.map(&:person)
    sender = FormReminderSender.new(@form, pending)
    sender.send!(sent_by: current_user.person, filter: { team_id: team&.id }.compact)
    redirect_to form_path(@form, team_id: team&.id), notice: "Sent #{helpers.pluralize(sender.recipients.size, "reminder")} about #{helpers.pluralize(pending.size, "person", plural: "people")}.", status: :see_other
  end

  # GET /forms/1/results
  def results
    @teams = helpers.form_team_choices(@form)
    @team = @teams.detect { |team| team.id == params[:team_id] }
    @version = params[:version] == "latest" ? :latest : :active
    @report = FormReport.new(@form, viewer: current_user.person, team: @team, version: @version)
    @profile_fields = helpers.form_profile_field_choices(current_user.person)
    @selected_fields = @profile_fields.select { |field| Array(params[:field_ids]).include?(field.id) }

    respond_to do |format|
      format.html
      format.csv do
        send_data helpers.form_results_csv(@report, @selected_fields), filename: "#{@form.key}-#{Date.current.iso8601}.csv", type: "text/csv"
      end
    end
  end

  # GET /forms/1/tally
  # With an event, the population can be the people who said they're coming
  # or the people who checked in.
  def tally
    unless policy(@form).show?
      # Shared totals only: everyone asked, no names, no filters.
      @shared = true
      @report = FormReport.new(@form, viewer: current_user.person, shared_totals: true)
      @questions = @report.questions
      return
    end

    @teams = helpers.form_team_choices(@form)
    @team = @teams.detect { |team| team.id == params[:team_id] }
    @event = @form.event || policy_scope(Event).find_by(id: params[:event_id])
    @basis = %w[ expected checked_in ].include?(params[:basis]) && @event ? params[:basis] : "asked"
    only = nil
    if @basis != "asked"
      sheet = FormOrderSheet.new(form: @form, event: @event, viewer: current_user.person, basis: @basis)
      only = sheet.population.map(&:id)
      @basis_missing = !sheet.basis_available?
    end
    @report = FormReport.new(@form, viewer: current_user.person, team: @team, only: only)
    @questions = @report.questions.select { |question| helpers.form_tallyable?(question) }
  end

  # GET /forms/order_sheet?form_id=&event_id=&basis=&question_ids[]=&field_ids[]=
  # One form's answers for an event's people: what to order, and for whom.
  def order_sheet
    authorize Form, :index?
    viewer = current_user.person
    @forms = Form.where(status: %i[ open closed ]).includes(:team).order(:title).select { |form| policy(form).show? }
    @form = @forms.detect { |form| form.id == params[:form_id] }
    @events = policy_scope(Event).where(start_time: 2.months.ago..4.months.from_now).order(:start_time).to_a
    @event = policy_scope(Event).find_by(id: params[:event_id])
    @events.unshift(@event) if @event && !@events.include?(@event)
    @layout = params[:layout] == "labels" ? "labels" : "list"
    return unless @form

    @choices = @form.answerable_questions.reject(&:intent?)
    @profile_fields = helpers.form_profile_field_choices(viewer)
    questions = @choices.select { |question| Array(params[:question_ids]).include?(question.id) }
    questions = @choices.select { |question| %w[ select multi_select ].include?(question.value_type.data_type) } if params[:question_ids].nil?
    fields = @profile_fields.select { |field| Array(params[:field_ids]).include?(field.id) }
    @sheet = FormOrderSheet.new(form: @form, event: @event, viewer: viewer, basis: params[:basis], questions: questions, fields: fields)
  end

  # GET /forms/1/preview
  def preview
    @preview = Preview.new(params.dig(:preview, :viewer_id), params.dig(:preview, :subject_id))
    @viewer = @preview.viewer
    @subject = @preview.subject
    @access = FormAccess.new(@viewer, @subject, @form) if @viewer && @subject
  end

  private
    def set_form
      @form = authorize Form.find(params[:id])
      @tab = params[:tab].presence_in(EDIT_TABS) || "details"
    end

    def require_feature
      redirect_to root_path, notice: "Forms are turned off" unless GatherPack::Features.enabled?(:forms)
    end

    def form_params
      permitted = [ :title, :description, :team_id, :audience_badge_id, :respond_permission, :read_permission,
        :opens_at, :closes_at, :allow_updates, :late_entry, :reconfirm_on_profile_change, :event_id, :totals_visibility, :leader_todo ]
      # A completion badge marks people's status, so only admins set it.
      # Neither badge setting changes while Badges are turned off.
      badges = GatherPack::Features.enabled?(:badges)
      permitted << :completion_badge_id if current_user.admin? && badges
      permitted.delete(:audience_badge_id) unless badges
      permitted << :key if @form.nil? || @form.new_record?
      params.require(:form).permit(*permitted)
    end
end
