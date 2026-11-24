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
  before_action :set_form, except: %i[ index new create print_list ]

  # GET /forms?q[title_i_cont]=
  def index
    authorize Form
    @entries = helpers.form_entries_for(current_user.person)
    managed = policy_scope(Form).visible
    @q = managed.ransack(params[:q])
    @managed = @q.result.includes(:team).order(Arel.sql("status = 1 DESC"), :title)
    # Forms the viewer can see others' answers to without running them (a
    # badge grant or a wide read level), so they have a way to get there.
    @shared = Form.where(status: %i[ open closed ]).where.not(id: managed.select(:id)).includes(:team)
      .order(Arel.sql("status = 1 DESC"), :title).select { |form| policy(form).show? }
  end

  # GET /forms/1?team_id=&status=&version=&who=&question_id=&answers[question_id][]=&columns_for=&question_ids[]=&show_status=&show_submitted=&field_ids[]=&layout=&totals=
  # GET /forms/1.csv?...&tf[key]=&tf_sort=&tf_dir=
  # Everyone the form asks (or the people chosen under "Who to include",
  # FormPopulation), with their status, answers and the totals, as a table,
  # labels or CSV.
  def show
    viewer = current_user.person
    @teams = helpers.form_team_choices(@form)
    @team = @teams.detect { |team| team.id == params[:team_id] }
    @status = FormReport::STATUSES.include?(params[:status]) ? params[:status] : nil
    @version = params[:version] == "latest" ? :latest : :active
    @layout = params[:layout] == "labels" ? "labels" : "list"
    @totals_hidden = params[:totals] == "hidden"

    # "Who to include" offers every form the viewer can see results for;
    # that list is only built when it's chosen from, or for the lazy frame
    # under More choices.
    if params[:frame] == "who_to_include"
      load_population_choices
      @population = FormPopulation.new(source: "asked", viewer: viewer, form: @form)
      return render "who_to_include", layout: false
    end
    if POPULATION_PARAMS.any? { |key| params[key].present? }
      load_population_choices
      @population = FormPopulation.from_params(params, viewer: viewer, form: @form, forms: @source_forms, events: policy_scope(Event))
    else
      @population = FormPopulation.new(source: "asked", viewer: viewer, form: @form)
    end
    only = @population.ids if @population.source == "answered"
    @report = FormReport.new(@form, viewer: viewer, team: @team, version: @version, only: only)
    # Remind always covers everyone asked in the team, as its page does.
    @remind_report = only ? FormReport.new(@form, viewer: viewer, team: @team) : @report
    @rows = @status ? @report.rows.select { |row| row.status == @status } : @report.rows
    load_outside_people(viewer) if only

    # Every question and no profile details, until the column tick boxes
    # for this form are sent. Profile columns from an old results link count.
    @questions = @report.questions
    @questions = @questions.select { |question| Array(params[:question_ids]).include?(question.id) } if params[:columns_for] == @form.id
    # Status and Submitted are ticks of the same list, on until it is sent.
    @show_status = params[:columns_for] != @form.id || params[:show_status] == "1"
    @show_submitted = params[:columns_for] != @form.id || params[:show_submitted] == "1"
    @profile_fields = helpers.form_profile_field_choices(viewer)
    @selected_fields = @profile_fields.select { |field| Array(params[:field_ids]).include?(field.id) }
    @options = show_options

    respond_to do |format|
      format.html
      format.csv do
        # The heading filters and sort carried from the table (tf, tf_sort, tf_dir).
        carried = TableFilterParams.new(params[:tf], sort: params[:tf_sort], dir: params[:tf_dir])
        rows = helpers.form_results_filtered_rows(@form, @report, @rows, carried, questions: @questions, fields: @selected_fields, status: @show_status, submitted: @show_submitted)
        send_data helpers.form_results_csv(@report, @selected_fields, questions: @questions, rows: rows, status: @show_status, submitted: @show_submitted), filename: "#{@form.key}-#{Date.current.iso8601}.csv", type: "text/csv"
      end
    end
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
  # The "Taking answers" choices on the Responses tab.
  TAKING_ANSWERS = %w[ draft open closed ].freeze
  # Params that pick people under "Who to include" (FormPopulation).
  POPULATION_PARAMS = %i[ who question_id event_id ].freeze

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
      @form.form_audience_rules.create!(effect: :include, target_type: :team, team: @form.default_audience_team)
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
    if allowed && @form.valid? && taking_answers_allowed? && @form.save
      notice = "Form was saved."
      notice += helpers.form_published_notice(params[:reconfirm] == "1") if @form.publish_changes!(reconfirm: params[:reconfirm] == "1")
      redirect_to edit_form_path(@form, tab: @tab), notice: notice, status: :see_other
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
    notice = "Form was duplicated. Its responses weren't copied."
    if @form.badge_settings_left_off?(copy)
      notice += current_user.admin? ? " Some badge settings weren't copied because they're no longer allowed." : " Its badge settings weren't copied: only an admin can add them."
    end
    redirect_to edit_form_path(copy, tab: "details"), notice: notice, status: :see_other
  end

  # GET /forms/1/reminder
  # Who Remind will email, the messages, and a preview, before sending.
  def reminder
    load_reminder
  end

  # POST /forms/1/remind
  def remind
    load_reminder
    return render :reminder, status: :unprocessable_content if params[:preview]

    sender = @senders.fetch(@include_guardians)
    return redirect_to form_path(@form, team_id: @team&.id), notice: "Nobody to remind.", status: :see_other if sender.recipients.empty?

    saved = { reminder_message: FormReminderSender.stored(params[:message]) } if params.key?(:message)
    saved = (saved || {}).merge(guardian_reminder_message: FormReminderSender.stored(params[:guardian_message])) if params.key?(:guardian_message)
    # Only the messages change, so the form's own checks (which depend on
    # other records) don't get a say in whether reminders go out.
    @form.assign_attributes(saved) if saved
    @form.save!(validate: false) if @form.changed?
    sender.send!(sent_by: current_user.person, filter: { team_id: @team&.id }.compact)
    redirect_to form_path(@form, team_id: @team&.id), notice: "Sent #{helpers.pluralize(sender.recipients.size, "reminder")} about #{helpers.pluralize(@pending.size, "person", plural: "people")}.", status: :see_other
  end

  # GET /forms/1/results
  # The form page shows the answers now; old links land there.
  def results
    redirect_to form_path(@form, format: (:csv if request.format.csv?), params: request.query_parameters)
  end

  # GET /forms/1/tally
  # The totals are on the form page. People the form only shares its totals
  # with get them here: everyone asked, no names, no filters.
  def tally
    return redirect_to form_path(@form, params: request.query_parameters) if policy(@form).show?

    @report = FormReport.new(@form, viewer: current_user.person, shared_totals: true)
    @questions = @report.questions
  end

  # GET /forms/print_list?form_id=&event_id=
  # Picks a form, then sends you to its page, where the list is printed.
  def print_list
    authorize Form, :index?
    load_population_choices
    @forms = @source_forms
    form = @forms.detect { |candidate| candidate.id == params[:form_id] }
    redirect_to form_path(form, params: request.query_parameters.except("form_id")) if form
  end

  # GET /forms/1/preview
  def preview
    @preview = Preview.new(params.dig(:preview, :viewer_id), params.dig(:preview, :subject_id))
    @viewer = @preview.viewer
    @subject = @preview.subject
    @access = FormAccess.new(@viewer, @subject, @form) if @viewer && @subject
  end

  private
    # The page's current choices, for links that change one of them.
    def show_options
      columns = { columns_for: @form.id, question_ids: @questions.map(&:id), show_status: (@show_status ? "1" : nil), show_submitted: (@show_submitted ? "1" : nil) } if @questions != @report.questions || !@show_status || !@show_submitted
      population = { who: "answered", question_form_id: @population.question&.form_id, question_id: @population.question&.id,
        answers: @population.question && { @population.question.id => @population.answers } } if @population.source == "answered"
      { team_id: @team&.id, status: @status, version: (@version == :latest ? "latest" : nil), field_ids: @selected_fields.map(&:id),
        layout: (@layout == "labels" ? "labels" : nil), totals: (@totals_hidden ? "hidden" : nil) }.merge(columns || {}, population || {}).compact_blank
    end

    # A "Taking answers" choice that the form's own times would undo:
    # FormScheduleJob opens a draft past its Opens time and closes an open
    # form past its Deadline. "Yes, open now" also needs someone to ask.
    def taking_answers_allowed?
      return true unless @form.will_save_change_to_status?
      message = if @form.open? && !@form.openable?
        "Add someone to ask before opening the form."
      elsif @form.open? && @form.closes_at&.past?
        "The deadline has passed: move it first."
      elsif @form.draft? && @form.opens_at&.past?
        "Opens is in the past: change it or choose No, closed."
      end
      return true unless message
      @form.errors.add(:status, message)
      false
    end

    # People picked under "Who to include" that this form's table can't
    # list: those it doesn't ask (shown as "Haven't answered") and those
    # whose answers the viewer can't see (counted). Nobody silently drops.
    def load_outside_people(viewer)
      split = FormPrintList.new(form: @form, viewer: viewer, source: @population)
      in_team = @team ? @team.descendant_people.ids.to_set : nil
      keep = ->(line) { in_team.nil? || in_team.include?(line.person.id) }
      @outside = @status ? [] : split.no_choice.reject(&:row).select(&keep)
      @outside_list = split
      @not_shown_count = split.hidden.count(&keep)
    end

    def load_population_choices
      @source_forms = Form.where(status: %i[ open closed ]).includes(:team, :event, :form_questions).order(:title).select { |form| policy(form).show? }
    end

    def set_form
      @form = authorize Form.find(params[:id])
      @tab = params[:tab].presence_in(EDIT_TABS) || "details"
    end

    # The people still owing a response in the team filter, and a sender
    # for each guardian choice, so the screen can switch between them. The
    # choice starts off on a form's first reminder and on after that.
    def load_reminder
      @team = Team.find_by(id: params[:team_id])
      report = FormReport.new(@form, viewer: current_user.person, team: @team)
      @pending = FormPending.new(@form, among: report.people).people
      @include_guardians = params.key?(:include_guardians) ? params[:include_guardians] == "1" : @form.form_reminders.exists?
      messages = { message: params[:message], guardian_message: params[:guardian_message] }
      @senders = [ true, false ].index_with { |include| FormReminderSender.new(@form, @pending, include_guardians: include, **messages) }
    end

    def require_feature
      redirect_to root_path, notice: "Forms are turned off" unless GatherPack::Features.enabled?(:forms)
    end

    def form_params
      permitted = [ :title, :description, :team_id, :audience_badge_id, :respond_permission, :read_permission,
        :opens_at, :closes_at, :allow_updates, :late_entry, :reconfirm_on_profile_change, :event_id, :totals_visibility, :leader_todo,
        :expiry, :expires_on, :valid_for_months ]
      # A completion badge marks people's status, so only admins set it.
      # Neither badge setting changes while Badges are turned off.
      badges = GatherPack::Features.enabled?(:badges)
      permitted << :completion_badge_id if current_user.admin? && badges
      permitted.delete(:audience_badge_id) unless badges
      permitted << :auto_reminder_days if GatherPack::Features.enabled?(:forms_auto_reminders)
      permitted << :key if @form.nil? || @form.new_record?
      # Taking answers, on the Responses tab. Archiving is its own action,
      # and an archived form isn't reopened from here.
      permitted << :status if @form&.persisted? && !@form.archived? && TAKING_ANSWERS.include?(params.dig(:form, :status))
      # Who is asked and who may answer decide who gets a completion badge
      # (FormPolicy#change_audience?).
      permitted -= [ :respond_permission, :audience_badge_id ] if @form&.persisted? && policy(@form).audience_locked?
      params.require(:form).permit(*permitted)
    end
end
